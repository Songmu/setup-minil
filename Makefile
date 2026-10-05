.PHONY: check test integration

check:
	./scripts/check-runtime
	./scripts/check-snapshots
	for script in scripts/*; do perl -I scripts -c "$$script" || exit; done
	for script in test/*.sh; do bash -n "$$script" || exit; done

test: check
	./test/unit.t

integration: check
	./test/smoke.sh
