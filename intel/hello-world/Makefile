hello: ./target/hello.o
	ld ./target/hello.o -o ./target/hello

./target/hello.o: hello.s
	mkdir -p ./target
	nasm -f elf64 -g -F dwarf hello.s -o ./target/hello.o

