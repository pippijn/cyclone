.PHONY: build boot

build: ; @omake
boot: ; @omake $@

%:
	@omake $@
