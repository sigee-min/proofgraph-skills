.PHONY: smoke e2e self-check

smoke:
	SIGEE_VALIDATION_MODE=framework bash skills/tech-developer/scripts/test_smoke.sh --mode framework

e2e:
	SIGEE_VALIDATION_MODE=framework bash skills/tech-developer/scripts/test_e2e.sh --mode framework

self-check:
	bash skills/tech-developer/scripts/self_check.sh --scope all
