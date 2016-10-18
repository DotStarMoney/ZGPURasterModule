
library ieee;                                   
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity intXor is
	generic(
		BIT_WIDTH : natural
	);
	port(
		a : in integer range -2**BIT_WIDTH to 2**BIT_WIDTH-1;
		b : in integer range -2**BIT_WIDTH to 2**BIT_WIDTH-1;
		o : out integer range -2**BIT_WIDTH to 2**BIT_WIDTH-1
	);
end intXor;

architecture struc of intXor is
	begin
		o <= to_unsigned(a, a'length) xor to_unsigned(b, b'length);
end struc;