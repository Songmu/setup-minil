.PHONY: check test integration

check:
	./scripts/check-runtime
	./scripts/check-snapshots
	for script in scripts/check-runtime scripts/setup-minil scripts/update-runtime scripts/update-snapshots test/*.sh; do \
		bash -n "$$script" || exit; \
	done
	perl -c scripts/check-snapshots

test: check
	./test/smoke.sh
	bash ./test/tool-cache.sh
	bash ./test/snapshots.sh

integration: check
	SETUP_MINIL_INTEGRATION=true ./test/smoke.sh
