dev:
	@docker-compose -f docker-compose.dev.yml up -d
	@sleep 10
	@./scripts/vault-init.sh
	@docker-compose -f qkms/docker-compose.dev.yml up -d

prod:
	@docker-compose -f docker-compose.prod.yml up -d
	@sleep 10
	@./scripts/vault-init-tls.sh
	@docker-compose -f qkms/docker-compose.prod.yml up -d
	
down:
	@docker-compose -f qkms/docker-compose.dev.yml down -v --timeout 0
	@docker-compose -f docker-compose.dev.yml down -v --timeout 0