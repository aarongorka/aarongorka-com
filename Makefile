build:
	hugo --cleanDestinationDir

test:
	cfn-lint -t cloudformation.yml

start:
	hugo server --buildDrafts --bind 0.0.0.0

deploy:
	stacker build stacker.yml --tail --recreate-failed

diff:
	stacker diff stacker.yml

syncToS3:
	aws s3 sync --no-progress --delete --cache-control 'max-age=3155695200' public/ s3://$(DOMAIN_NAME)/

cacheInvalidation:
	aws cloudfront create-invalidation --distribution-id=$(shell aws cloudformation --region us-east-1 describe-stacks --stack-name $(AWS_CLOUDFORMATION_STACK_NAME) --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionId`].OutputValue' --output=text) --paths "/*"

clean:
	-rm -rf public/
