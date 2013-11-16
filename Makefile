compile: clean
	coffee -bco lib src

watch:
	coffee -bcwo lib src

clean:
	rm -rf lib/*

docs:
	node lib/cdoc.js src doc
