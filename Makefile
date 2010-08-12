all: 
	@erl -make
	@escript release/build_rel.escript boot redis `pwd`/ebin

clean:
	rm -f ebin/*.beam