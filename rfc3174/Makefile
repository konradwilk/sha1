CC=gcc
CFLAGS=-I.
DEPS = sha1.h
OBJ = sha1test.o sha1.o
TARGET = sha1test

%.o: %.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

$(TARGET): $(OBJ)
	$(CC) -o $@ $^ $(CFLAGS)

clean:
	rm -f *.o $(TARGET)
