.PHONY: test* resolve* instantiate*

JULIA = julia
JULIA_MAIN = julia1.4
JULIA_OPTS = --startup-file=no --color=yes

test: test-environments/main

test-environments/main \
: test-%:
	CI=true JULIA_NUM_THREADS=2 $(JULIA) $(JULIA_OPTS) --project=test/$* test/runtests.jl

TEST_JULIA = test-v1.4 test-v1.5 test-v1.6

test-all:$(TEST_JULIA)
$(TEST_JULIA): test-v%:
	make JULIA=julia$* test-environments/main

instantiate: instantiate-test/environments/main

instantiate-test/environments/main \
: instantiate-%: resolve-%
	$(JULIA_MAIN) $(JULIA_OPTS) --project=$* -e 'using Pkg; Pkg.instantiate()'

resolve: resolve-test/environments/main

resolve-test/environments/main \
: resolve-%:
	$(JULIA_MAIN) $(JULIA_OPTS) --project=$* -e 'using Pkg; Pkg.resolve()'
