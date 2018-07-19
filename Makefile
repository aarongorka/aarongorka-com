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

syncToS3: $(DOTENV_TARGET)
	docker-compose run --rm aws make _syncToS3

syncMediaToS3: $(DOTENV_TARGET)
	docker-compose run --rm aws make _syncMediaToS3

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
	aws s3 sync --no-progress --delete --exclude 'media/*' --cache-control 'max-age=604800' public/ s3://$(DOMAIN_NAME)/

_syncMediaToS3:
	aws s3 sync --no-progress --cache-control 'max-age=604800' static/media/ s3://$(DOMAIN_NAME)/media/

_cacheInvalidation:
	aws cloudfront create-invalidation --distribution-id=$(shell aws cloudformation --region ap-southeast-2 describe-stacks --stack-name $(AWS_CLOUDFORMATION_STACK_NAME) --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionId`].OutputValue' --output=text) --paths "/*"
