CFLAGS += -std=c99
CFLAGS += -O2
CFLAGS += -Wall

LDFLAGS += -lusb

.PHONY: clean distclean

all: lcd

lcd: drv_LCD2USB.o
	$(CC) -o $@ $^ $(LDFLAGS)

clean:
	rm -f *.o

distclean: clean
	rm -f lcd
