build/lori: build lori/*.pony
	ponyc lori -o build --debug

build:
	mkdir build

test: build/lori
	build/lori

clean:
	rm -rf build

.PHONY: clean test
