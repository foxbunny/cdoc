compile: clean
	livescript -bco lib src

watch:
	livescript -bcwo lib src

clean:
	rm -rf lib/*

docs:
	node bin/cli.js src doc
