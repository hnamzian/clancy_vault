dev:
	@docker-compose -f docker-compose.yml up -d
	@sleep 10
	@./scripts/vault-init.sh
	@docker-compose -f qkms/docker-compose.yml up -d

down:
	@docker-compose -f qkms/docker-compose.yml down -v --timeout 0
	@docker-compose -f docker-compose.yml down -v --timeout 0