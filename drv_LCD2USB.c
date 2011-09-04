/* $Id: drv_LCD2USB.c 773 2007-02-25 12:39:09Z michael $
 * $URL: https://ssl.bulix.org/svn/lcd4linux/branches/0.10.1/drv_LCD2USB.c $
 *
 * driver for USB2LCD display interface
 * see http://www.harbaum.org/till/lcd2usb for schematics
 *
 * Copyright 2005 Till Harbaum <till@harbaum.org>
 * Copyright 2005 The LCD4Linux Team <lcd4linux-devel@users.sourceforge.net>
 *
 * This file is part of LCD4Linux.
 *
 * LCD4Linux is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 *
 * LCD4Linux is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */
#include <stdlib.h>
#include <stdarg.h>
#include <syslog.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <errno.h>
#include <unistd.h>
#include <termios.h>
#include <fcntl.h>
#include <ctype.h>
#include <sys/ioctl.h>
#include <sys/time.h>

#include <usb.h>

static int DCOLS = 40, DROWS = 4;

/* vid/pid donated by FTDI */
#define LCD_USB_VENDOR 0x0403
#define LCD_USB_DEVICE 0xC630

/* number of buttons on display */
#define L2U_BUTTONS        (2)

#define LCD_ECHO           (0<<5)
#define LCD_CMD            (1<<5)
#define LCD_DATA           (2<<5)
#define LCD_SET            (3<<5)
#define LCD_GET            (4<<5)

/* target is a bit map for CMD/DATA */
#define LCD_CTRL_0              (1<<3)
#define LCD_CTRL_1              (1<<4)
#define LCD_BOTH           (LCD_CTRL_0 | LCD_CTRL_1)

/* target is value to set */
#define LCD_SET_CONTRAST   (LCD_SET | (0<<3))
#define LCD_SET_BRIGHTNESS (LCD_SET | (1<<3))
#define LCD_SET_RESERVED0  (LCD_SET | (2<<3))
#define LCD_SET_RESERVED1  (LCD_SET | (3<<3))

/* target is value to get */
#define LCD_GET_FWVER      (LCD_GET | (0<<3))
#define LCD_GET_BUTTONS    (LCD_GET | (1<<3))
#define LCD_GET_CTRL       (LCD_GET | (2<<3))
#define LCD_GET_RESERVED1  (LCD_GET | (3<<3))

static char Name[] = "LCD2USB";
static char *device_id = NULL, *bus_id = NULL;

static usb_dev_handle *lcd;
static int controllers = 0;

extern int usb_debug;

/****************************************/
/***  hardware dependant functions    ***/
/****************************************/

static int drv_L2U_open(char *bus_id, char *device_id)
{
    struct usb_bus *busses, *bus;
    struct usb_device *dev;

    lcd = NULL;

    printf("%s: scanning USB for LCD2USB interface...\n", Name);

    if (bus_id != NULL)
	printf("%s: scanning for bus id: %s\n", Name, bus_id);

    if (device_id != NULL)
	printf("%s: scanning for device id: %s\n", Name, device_id);

    usb_debug = 0;

    usb_init();
    usb_find_busses();
    usb_find_devices();
    busses = usb_get_busses();

    for (bus = busses; bus; bus = bus->next) {
	/* search this bus if no bus id was given or if this is the given bus id */
	if (!bus_id || (bus_id && !strcasecmp(bus->dirname, bus_id))) {

	    for (dev = bus->devices; dev; dev = dev->next) {
		/* search this device if no device id was given or if this is the given device id */
		if (!device_id || (device_id && !strcasecmp(dev->filename, device_id))) {

		    if ((dev->descriptor.idVendor == LCD_USB_VENDOR) && (dev->descriptor.idProduct == LCD_USB_DEVICE)) {
			printf("%s: found LCD2USB interface on bus %s device %s\n", Name, bus->dirname, dev->filename);
			lcd = usb_open(dev);
			if (usb_claim_interface(lcd, 0) < 0) {
			    fprintf(stderr, "%s: usb_claim_interface() failed!\n", Name);
			    return -1;
			}
			return 0;
		    }
		}
	    }
	}
    }
    return -1;
}


static int drv_L2U_send(int request, int value, int index)
{
    if (usb_control_msg(lcd, USB_TYPE_VENDOR, request, value, index, NULL, 0, 1000) < 0) {
	fprintf(stderr, "%s: USB request failed! Trying to reconnect device.\n", Name);

	usb_release_interface(lcd, 0);
	usb_close(lcd);

	/* try to close and reopen connection */
	if (drv_L2U_open(bus_id, device_id) < 0) {
	    fprintf(stderr, "%s: could not re-detect LCD2USB USB LCD\n", Name);
	    return -1;
	}
	/* and try to re-send command */
	if (usb_control_msg(lcd, USB_TYPE_VENDOR, request, value, index, NULL, 0, 1000) < 0) {
	    fprintf(stderr, "%s: retried USB request failed, aborting!\n", Name);
	    return -1;
	}

	printf("%s: Device successfully reconnected.\n", Name);
    }

    return 0;
}

/* send a number of 16 bit words to the lcd2usb interface */
/* and verify that they are correctly returned by the echo */
/* command. This may be used to check the reliability of */
/* the usb interfacing */
#define ECHO_NUM 100

int drv_L2U_echo(void)
{
    int i, nBytes, errors = 0;
    unsigned short val, ret;

    for (i = 0; i < ECHO_NUM; i++) {
	val = rand() & 0xffff;

	nBytes = usb_control_msg(lcd,
				 USB_TYPE_VENDOR | USB_RECIP_DEVICE | USB_ENDPOINT_IN,
				 LCD_ECHO, val, 0, (char *) &ret, sizeof(ret), 1000);

	if (nBytes < 0) {
	    fprintf(stderr, "%s: USB request failed!\n", Name);
	    return -1;
	}

	if (val != ret)
	    errors++;
    }

    if (errors) {
	fprintf(stderr, "%s: ERROR, %d out of %d echo transfers failed!\n", Name, errors, ECHO_NUM);
	return -1;
    }

    printf("%s: echo test successful\n", Name);

    return 0;
}

/* get a value from the lcd2usb interface */
static int drv_L2U_get(unsigned char cmd)
{
    unsigned char buffer[2];
    int nBytes;

    /* send control request and accept return value */
    nBytes = usb_control_msg(lcd,
			     USB_TYPE_VENDOR | USB_RECIP_DEVICE | USB_ENDPOINT_IN,
			     cmd, 0, 0, (char *) buffer, sizeof(buffer), 1000);

    if (nBytes < 0) {
	fprintf(stderr, "%s: USB request failed!\n", Name);
	return -1;
    }

    return buffer[0] + 256 * buffer[1];
}

/* get lcd2usb interface firmware version */
static void drv_L2U_get_version(void)
{
    int ver = drv_L2U_get(LCD_GET_FWVER);

    if (ver != -1)
	printf("%s: firmware version %d.%02d\n", Name, ver & 0xff, ver >> 8);
    else
	printf("%s: unable to read firmware version\n", Name);
}

/* get the bit mask of installed LCD controllers (0 = no */
/* lcd found, 1 = single controller display, 3 = dual */
/* controller display */
static void drv_L2U_get_controllers(void)
{
    controllers = drv_L2U_get(LCD_GET_CTRL);

    if (controllers != -1) {
	if (controllers)
	    printf("%s: installed controllers: %s%s\n", Name,
		 (controllers & 1) ? "CTRL0" : "", (controllers & 2) ? " CTRL1" : "");
	else
	    printf("%s: no controllers found\n", Name);
    } else {
	fprintf(stderr, "%s: unable to read installed controllers\n", Name);
	controllers = 0;	/* don't access any controllers */
    }

    /* convert into controller map matching our protocol */
    controllers = ((controllers & 1) ? LCD_CTRL_0 : 0) | ((controllers & 2) ? LCD_CTRL_1 : 0);
}

/* to increase performance, a little buffer is being used to */
/* collect command bytes of the same type before transmitting them */
#define BUFFER_MAX_CMD 4	/* current protocol supports up to 4 bytes */
int buffer_current_type = -1;	/* nothing in buffer yet */
int buffer_current_fill = 0;	/* -"- */
unsigned char buffer[BUFFER_MAX_CMD];

/* command format: 
 * 7 6 5 4 3 2 1 0
 * C C C T T R L L
 *
 * TT = target bit map 
 * R = reserved for future use, set to 0
 * LL = number of bytes in transfer - 1 
 */

/* flush command queue due to buffer overflow / content */
/* change or due to explicit request */
static void drv_L2U_flush(void)
{
    int request, value, index;

    /* anything to flush? ignore request if not */
    if (buffer_current_type == -1)
	return;

    /* build request byte */
    request = buffer_current_type | (buffer_current_fill - 1);

    /* fill value and index with buffer contents. endianess should IMHO not */
    /* be a problem, since usb_control_msg() will handle this. */
    value = buffer[0] | (buffer[1] << 8);
    index = buffer[2] | (buffer[3] << 8);

    if (controllers) {
	/* send current buffer contents */
	drv_L2U_send(request, value, index);
    }

    /* buffer is now free again */
    buffer_current_type = -1;
    buffer_current_fill = 0;
}

/* enqueue a command into the buffer */
static void drv_L2U_enqueue(int command_type, int value)
{
    if ((buffer_current_type >= 0) && (buffer_current_type != command_type))
	drv_L2U_flush();

    /* add new item to buffer */
    buffer_current_type = command_type;
    buffer[buffer_current_fill++] = value;

    /* flush buffer if it's full */
    if (buffer_current_fill == BUFFER_MAX_CMD)
	drv_L2U_flush();
}

static void drv_L2U_command(const unsigned char ctrl, const unsigned char cmd)
{
    drv_L2U_enqueue(LCD_CMD | (ctrl & controllers), cmd);
}


static void drv_L2U_clear(void)
{
    drv_L2U_command(LCD_BOTH, 0x01);	/* clear display */
    drv_L2U_command(LCD_BOTH, 0x03);	/* return home */
}

static void drv_L2U_write(int row, const int col, const char *data, int len)
{
    int pos, ctrl = LCD_CTRL_0;

    /* displays with more two rows and 20 columns have a logical width */
    /* of 40 chars and use more than one controller */
    if ((DROWS > 2) && (DCOLS > 20) && (row > 1)) {
	/* use second controller */
	row -= 2;
	ctrl = LCD_CTRL_1;
    }

    /* 16x4 Displays use a slightly different layout */
    if (DCOLS == 16 && DROWS == 4) {
	pos = (row % 2) * 64 + (row / 2) * 16 + col;
    } else {
	pos = (row % 2) * 64 + (row / 2) * 20 + col;
    }

    drv_L2U_command(ctrl, 0x80 | pos);

    while (len--) {
	drv_L2U_enqueue(LCD_DATA | (ctrl & controllers), *data++);
    }

    drv_L2U_flush();
}

static int drv_L2U_contrast(int contrast)
{
    if (contrast < 0)
	contrast = 0;
    if (contrast > 255)
	contrast = 255;

    drv_L2U_send(LCD_SET_CONTRAST, contrast, 0);

    return contrast;
}

static int drv_L2U_brightness(int brightness)
{
    if (brightness < 0)
	brightness = 0;
    if (brightness > 255)
	brightness = 255;

    drv_L2U_send(LCD_SET_BRIGHTNESS, brightness, 0);

    return brightness;
}

static int drv_L2U_start()
{
    if (drv_L2U_open(NULL, NULL) < 0) {
	fprintf(stderr, "%s: could not find a LCD2USB USB LCD\n", Name);
	return -1;
    }

    /* test interface reliability */
    drv_L2U_echo();

    /* get some infos from the interface */
    drv_L2U_get_version();
    drv_L2U_get_controllers();
    if (!controllers)
	return -1;

    drv_L2U_clear();		/* clear display */

    return 0;
}

int main(int argc, char *argv[]) {
	if (argc > 1) {
		printf("lcd © 2010 Michael Stapelberg\n");
		printf("based on lcd4linux, see http://lcd4linux.sourceforge.net/\n");
		printf("Compiled for an %d x %d display\n", DCOLS, DROWS);
		printf("\n");
		printf("This tool pushes the lines it gets via stdin to an LCD display\n");
		printf("connected via LCD2USB. Lines may be ended by \\n and can only be\n");
		printf("up to 40 characters wide (or what your display size is).\n");
		return 0;
	}
	drv_L2U_start();
	int line = 0;
	while (1) {
		char buffer[41];
		int n, pos = 0;

		/* Read up to '\n' or DCOLS characters, whichever occurs earlier */
		while (((n = read(0, buffer + pos, 1)) > 0) && (pos < DCOLS)) {
			pos++;
			if (buffer[pos-1] == '\n')
				break;
		}
		buffer[pos-1] = '\0';

		if (n == 0) {
			/* on EOF, flush and exit */
			drv_L2U_write(line, 0, buffer, strlen(buffer));
			return 0;
		}

		/* exit on error */
		if (n < 0)
			return 1;

		drv_L2U_write(line, 0, buffer, strlen(buffer));
		line++;
		if (line != 0 && (line % 4) == 0) {
			line = 0;
			//drv_L2U_clear();
		}
	}
}
