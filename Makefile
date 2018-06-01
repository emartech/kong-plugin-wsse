SHELL=/bin/bash
.PHONY: help publish test

help: ## Show this help
	@echo "Targets:"
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/\(.*\):.*##[ \t]*/    \1 ## /' | sort | column -t -s '##'

up: ## Start containers
	docker-compose up -d

down: ##  Stops containers
	docker-compose down

restart: down up ## Restart containers

clear-db: ## Clears local db
	bash -c "rm -rf .docker"

build: ## Rebuild containers
	docker-compose build --no-cache

complete-restart: clear-db down up    ## Clear DB and restart containers

publish: ## Build and publish plugin to luarocks
	docker-compose run kong bash -c "cd /kong-plugins && chmod +x publish.sh && ./publish.sh"

test: ## Run tests
	docker-compose up -d
	docker-compose run kong bash -c "cd /kong && bin/busted /kong-plugins/spec"
	docker-compose down

dev-env: ## Creates a service (testapi), route (/) and consumer (TestUser)
	bash -c "curl -i -X POST --url http://localhost:8001/services/ --data 'name=testapi' --data 'url=http://mockbin.org/request'"
	bash -c "curl -i -X POST --url http://localhost:8001/services/testapi/routes/ --data 'paths[]=/'"
	bash -c "curl -i -X POST --url http://localhost:8001/services/testapi/plugins/ --data 'name=wsse'"
	bash -c "curl -i -X POST --url http://localhost:8001/consumers/ --data 'username=TestUser'"
	bash -c "curl -i -X POST --url http://localhost:8001/consumers/TestUser/wsse_key/ --data 'key=test_user001&secret=53cr37p455w0rd'"

wsse-key: ## Creates wsse key (test_user001) for test consumer (TestUser)
	bash -c "curl -i -X POST --url http://localhost:8001/consumers/TestUser/wsse_key/ --data 'key=test_user001&secret=53cr37p455w0rd'"

ping: ## Pings kong on localhost:8000
	bash -c "curl -i http://localhost:8000"

ssh: ## SSH into kong
	docker-compose run kong bash

db: ## Access DB ( works only after 'make ssh' in kong-plungins directory)
	psql -h kong-database -U kong
