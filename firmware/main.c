#include <stdint.h>

typedef struct {
	volatile uint32_t RX_FIFO;
	volatile uint32_t TX_FIFO;
	volatile uint32_t STAT_REG;
	volatile uint32_t CTRL_REG;
} XUartLite;

#define XUART0 ((XUartLite *)(0x40000000))

#define XUART_STAT_TX_FULL 0x08

void putchar(char ch)
{
	while (XUART0->STAT_REG & XUART_STAT_TX_FULL);
	XUART0->TX_FIFO = ch;
}

void print(const char * str)
{
	for (; *str; str++) {
		putchar(*str);
	}
}

const char * key_code = "01";

int main()
{
	volatile int i;
	
	for (;;) {
		print("\nPico-ISP Test\n");
		print("Current Key Code is: ");
		print(key_code);
		print("\n\n");
		for (i = 0; i < 1000000; i++);
	}
}