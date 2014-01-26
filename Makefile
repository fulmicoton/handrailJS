all: example

compile:
	@echo "#!/usr/bin/env casperjs" > handrail
	@coffee -p handrail.coffee >> handrail
	@chmod +x handrail

example:
	handrail example.md