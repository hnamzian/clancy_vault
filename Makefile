dev-up:
	@docker-compose -f ./dev/docker-compose.yml up -d
	@sleep 10
	@./dev/vault/scripts/vault-init.sh
	@docker-compose -f ./dev/qkms/docker-compose.yml up -d

dev-test:
	@./dev/test/qkms-test.sh

dev-down:
	@docker-compose -f ./dev/qkms/docker-compose.yml down -v --timeout 0
	@docker-compose -f ./dev/docker-compose.yml down -v --timeout 0
	sudo rm -rf ./dev/vault/data ./dev/vault/logs ./dev/vault/policies ./dev/vault/token ./dev/vault/unseal


prod-tls-up:
	@docker-compose -f ./prod-tls/ca/docker-compose.yml up -d
	@sleep 10
	@./prod-tls/ca/vault/scripts/unseal.sh
	@./prod-tls/ca/vault/scripts/init_ca.sh
	@docker-compose -f ./prod-tls/docker-compose.yml up -d
	@sleep 10
	@./prod-tls/vault/scripts/vault-init-tls.sh
	@docker-compose -f ./prod-tls/qkms/docker-compose.yml up -d
	
prod-tls-test:
	./prod-tls/test/qkms-test-tls.sh

prod-tls-down:
	@docker-compose -f ./prod-tls/ca/docker-compose.yml down -v --timeout 0
	@docker-compose -f ./prod-tls/qkms/docker-compose.yml down -v --timeout 0
	@docker-compose -f ./prod-tls/docker-compose.yml down -v --timeout 0
	sudo rm -rf ./prod-tls/vault/data ./prod-tls/vault/logs ./prod-tls/vault/policies ./prod-tls/vault/token ./prod-tls/vault/unseal
	sudo rm -rf ./prod-tls/ca/vault/data ./prod-tls/ca/vault/logs ./prod-tls/ca/vault/policies ./prod-tls/ca/vault/token ./prod-tls/ca/vault/unseal
	sudo rm -rf ./prod-tls/certs
