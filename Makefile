all: example

handrail:
	@echo "#!/usr/bin/env casperjs" > handrail
	@coffee -p handrail.coffee >> handrail
	@chmod +x handrail

example: handrail
	./handrail example.md