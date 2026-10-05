.PHONY: check test integration

check:
	./scripts/check-runtime
	./scripts/check-snapshots
	bash -n scripts/* test/*.sh

test: check
	./test/smoke.sh
	bash ./test/tool-cache.sh
	bash ./test/snapshots.sh

integration: check
	SETUP_MINIL_INTEGRATION=true ./test/smoke.sh
