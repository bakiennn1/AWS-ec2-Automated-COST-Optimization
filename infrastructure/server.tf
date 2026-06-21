provider "aws" {
	access_key = "mock_access_key"
	secret_key = "mock_secret_key"
	region = "ap-southeast-3"
	skip_credentials_validation = true
	skip_metadata_api_check = true
	skip_requesting_account_id = true

	endpoints {
		ec2 = "http://localhost:4566"
		lambda = "http://localhost:4566"
		iam = "http://localhost:4566"
		eventbridge = "http://localhost:4566"
	} 
}

resource "aws_instance" "development_server" {
	ami = "ami-df5dbec2"
	instance_type = "t2.micro"

	tags = {
		Name = "Dev_Server"
		AutoStop = "True"
		Environment = "Development"
	}
}

resource "aws_instance" "production_server" {
	ami = "ami-df5dbec2"
	instance_type = "t2.micro"

	tags = {
		Name = "Prod_Server"
		AutoStop = "False"
		Environment = "Production"
	}
}

resource "aws_iam_role" "lambda_role" {
	name = "onoff_role"

	assume_role_policy = jsonencode({
		Version = "2012-10-17"
		Statement = [
			{
				Action = "sts:AssumeRole"
				Effect = "Allow"
				Principal = { Service = "lambda.amazonaws.com"}
			}
		]
	})
}

resource "aws_iam_policy" "lambda_ec2_policy" {
	name = "onoff_policy"
	description = "Hanya untuk mematikan dan menyalakan server!"

	policy = jsonencode({
		Version = "2012-10-17"
		Statement = [
			{
				Effect = "Allow"
				Action = [
					"ec2:DescribeInstances",
					"ec2:StartInstances",
					"ec2:StopInstances"
				]
				Resource = "*"
			}
		]
	})
}

resource "aws_iam_role_policy_attachment" "attach_policy_to_role" {
	role = aws_iam_role.lambda_role.name
	policy_arn = aws_iam_policy.lambda_ec2_policy.arn
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/onoff_script.zip"

  source {
    content  = file("${path.module}/../script/onoff_script.py")
    filename = "onoff_script.py" #
  }
}

resource "aws_lambda_function" "ec2_onoff_lambda" {
	filename = data.archive_file.lambda_zip.output_path
	source_code_hash = data.archive_file.lambda_zip.output_base64sha256
	function_name = "ec2_onoff_automation"
	role = aws_iam_role.lambda_role.arn
	handler = "onoff_script.onoff"
	runtime = "python3.11"
	timeout = 60
}

resource "aws_cloudwatch_event_rule" "ec2_on" {
	name = "cron_start_dev_server"
	schedule_expression = "cron(0/4 * * * ? *)"
}

resource "aws_cloudwatch_event_target" "start_target" {
	rule = aws_cloudwatch_event_rule.ec2_on.name
	target_id = "TriggerLambdaStart"
	arn = aws_lambda_function.ec2_onoff_lambda.arn
	input = jsonencode({
		action = "start"
	})
}

resource "aws_cloudwatch_event_rule" "ec2_off" {
	name = "cron_stop_dev_server"
	schedule_expression = "cron(2/4 * * * ? *)"
}

resource "aws_cloudwatch_event_target" "stop_target" {
	rule = aws_cloudwatch_event_rule.ec2_off.name
	target_id = "TriggerLambdaStop"
	arn = aws_lambda_function.ec2_onoff_lambda.arn
	input = jsonencode({
		action = "stop"
	})
}

resource "aws_lambda_permission" "allow_start_cron" {
  statement_id  = "AllowExecutionFromEventBridgeStart"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_onoff_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_on.arn
}

resource "aws_lambda_permission" "allow_stop_cron" {
  statement_id  = "AllowExecutionFromEventBridgeStop"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_onoff_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_off.arn
}