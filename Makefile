dev:
	@docker-compose -f docker-compose.dev.yml up -d
	@sleep 10
	@./scripts/vault-init.sh
	@docker-compose -f qkms/docker-compose.dev.yml up -d

prod:
	@make ca
	@docker-compose -f docker-compose.prod.yml up -d
	@sleep 10
	@./scripts/vault-init-tls.sh
	@docker-compose -f qkms/docker-compose.prod.yml up -d
	
ca:
	@docker-compose -f ./CA/docker-compose.yml up -d
	@sleep 10
	@./CA/vault/scripts/unseal.sh
	@./CA/vault/scripts/init_ca.sh

down:
	@docker-compose -f qkms/docker-compose.dev.yml down -v --timeout 0
	@docker-compose -f docker-compose.dev.yml down -v --timeout 0
	@docker-compose -f ./CA/docker-compose.yml down -v --timeout 0
	sudo rm -rf ./vault/data ./vault/logs ./vault/policies ./vault/token ./vault/unseal
	sudo rm -rf ./CA/vault/data ./CA/vault/logs ./CA/vault/policies ./CA/vault/token ./CA/vault/unseal
	rm -rf certs

test-tls:
	./test/qkms-test-tls.sh