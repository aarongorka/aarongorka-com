ifdef DOTENV
	DOTENV_TARGET=dotenv
else
	DOTENV_TARGET=.env
endif

##################
# PUBLIC TARGETS #
##################
build: $(DOTENV_TARGET)
	docker-compose run --rm hugo --cleanDestinationDir

test: $(DOTENV_TARGET)
	docker-compose run cfn-python-lint cfn-lint -t cloudformation.yml

start: $(DOTENV_TARGET)
	docker-compose run --rm --service-ports hugo server --buildDrafts --bind 0.0.0.0

up: $(DOTENV_TARGET)
	docker-compose up -d hugo

syncToS3: $(DOTENV_TARGET)
	docker-compose run --rm aws make _syncToS3

cacheInvalidation: $(DOTENV_TARGET)
	docker-compose run --rm aws make _cacheInvalidation

deploy: $(DOTENV_TARGET)
	docker-compose run --rm stacker build stacker.yml --tail --recreate-failed

diff: $(DOTENV_TARGET)
	docker-compose run --rm stacker diff stacker.yml

###########
# ENVFILE #
###########
# Create .env based on .env.template if .env does not exist
.env:
	@echo "Create .env with .env.template"
	cp .env.template .env

# Create/Overwrite .env with $(DOTENV)
dotenv:
	@echo "Overwrite .env with $(DOTENV)"
	cp $(DOTENV) .env

$(DOTENV):
	$(info overwriting .env file with $(DOTENV))
	cp $(DOTENV) .env
.PHONY: $(DOTENV)

##################
# PRIVATE TARGET #
##################

_syncToS3:
	aws s3 sync --no-progress --delete --cache-control 'max-age=3155695200' public/ s3://$(DOMAIN_NAME)/

_cacheInvalidation:
	aws cloudfront create-invalidation --distribution-id=$(shell aws cloudformation --region us-east-1 describe-stacks --stack-name $(AWS_CLOUDFORMATION_STACK_NAME) --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionId`].OutputValue' --output=text) --paths "/*"

_clean:
	-rm -rf public/
