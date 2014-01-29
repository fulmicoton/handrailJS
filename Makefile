all: example

handrail:
	@echo "#!/usr/bin/env casperjs" > handrail
	@coffee -p handrail.coffee >> handrail
	@chmod +x handrail

example: handrail
	casperjs --engine=slimerjs handrail.coffee index.md 