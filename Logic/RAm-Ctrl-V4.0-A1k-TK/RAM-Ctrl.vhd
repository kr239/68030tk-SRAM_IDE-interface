----------------------------------------------------------------------------------
-- Company: A1K.org
-- Engineer: Matthias Heinrichs
-- 
-- Create Date:    22:08:21 07/13/2013 
-- Design Name: 030-SRAM-TK
-- Module Name:    RAMCtrl - Behavioral 
-- Project Name: SRAM-IDE-CPLD for 68030-TK
-- Target Devices: 9572XL-TQ100
-- Tool versions: 14.6
-- Description: This module generates signals for interfacing the SRAM and IDE, AutoConfig for RAM and IDE and switches the ROM-Enable line
--
-- Dependencies: none
--
-- Revision: 0.02 - everything seems to work
-- Revision 0.01 - File Created
-- Additional Comments: Yipieyayhea Schweinebacke!
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity RAMCtrl is
Port (
	reset 	: in  STD_LOGIC;		-- asynchronous reset
   clk 		: in  STD_LOGIC;     -- master clock input, active rising edge
	A 			: in 	STD_LOGIC_VECTOR(31 downto 0);                   
	SIZ 		: in 	STD_LOGIC_VECTOR(1 downto 0);                   
	nAS 		: in  STD_LOGIC;
	ECS 		: in  STD_LOGIC;
	nDS 		: in  STD_LOGIC;
	RW			: in  STD_LOGIC;
	IDE_WAIT	: in 	STD_LOGIC;
	IDE_IRQ	: in 	STD_LOGIC;

	D			: inout STD_LOGIC_VECTOR(3 downto 0);

	DSACK 	: out STD_LOGIC_VECTOR(1 downto 0);                   
	BYTE 		: out STD_LOGIC_VECTOR(3 downto 0);                   
	nRAM_SEL : out  STD_LOGIC:='1';
	OE 		: out  STD_LOGIC_VECTOR(1 downto 0);
	WE			: out  STD_LOGIC_VECTOR(1 downto 0);
	INT2		: out  STD_LOGIC:='1';
	IO4		: out  STD_LOGIC:='1';
	IO5		: out  STD_LOGIC:='1';
	STERM		: out  STD_LOGIC:='1';
	ROM_EN	: out  STD_LOGIC:='1';
	ROM_OE	: out  STD_LOGIC:='1';
	ROM_WE	: out  STD_LOGIC:='1';
	IDE_DIR	: out  STD_LOGIC:='1';
	IDE_R		: out  STD_LOGIC:='1';
	IDE_W		: out  STD_LOGIC:='1';
	IDE_A		: out  STD_LOGIC_VECTOR(2 downto 0);
	IDE_CS	: out  STD_LOGIC_VECTOR(1 downto 0);
	CIIN		: out  STD_LOGIC:='1' --this is AS_000 on the original HARMS-INTERFACE

	);
end RAMCtrl;

architecture Behavioral of RAMCtrl is
function MAX(LEFT, RIGHT: INTEGER) return INTEGER is
begin
	if LEFT > RIGHT then 
		return LEFT;
	else 
		return RIGHT;
	end if;
end;

constant IDE_WAITS : integer := 0;
constant ROM_WAITS : integer := 3;
constant RAM_WAITS : integer := 1;

constant IDE_DELAY : integer := MAX(1,MAX(IDE_WAITS,ROM_WAITS));
constant RAM_DELAY : integer := MAX(1,RAM_WAITS);

signal	MY_CYCLE: STD_LOGIC;
signal   IDE_SPACE:STD_LOGIC;
signal	AUTO_CONFIG:STD_LOGIC;
signal	AUTO_CONFIG_DONE:STD_LOGIC_VECTOR(1 downto 0);
signal	AUTO_CONFIG_DONE_CYCLE:STD_LOGIC_VECTOR(1 downto 0);
signal	SHUT_UP:STD_LOGIC_VECTOR(1 downto 0);
signal	BASEADR:STD_LOGIC_VECTOR(2 downto 0);
signal	BASEADR_4MB:STD_LOGIC_VECTOR(2 downto 0);
signal	IDE_BASEADR:STD_LOGIC_VECTOR(7 downto 0);
signal	Dout1:STD_LOGIC_VECTOR(3 downto 0);
signal	IDE_DSACK:STD_LOGIC_VECTOR(IDE_DELAY downto 0);
signal	DSACK_16BIT:STD_LOGIC;
signal	DSACK_32BIT:STD_LOGIC_VECTOR(RAM_DELAY downto 0);
signal	IDE_ENABLE:STD_LOGIC;
signal	RAM2MB:STD_LOGIC;
signal	RAM4MB:STD_LOGIC;
signal	ROM_OE_S:STD_LOGIC;
signal	IDE_R_S:STD_LOGIC;
signal	IDE_W_S:STD_LOGIC;
signal	AUTO_CONFIG_D0:STD_LOGIC;
signal	nAS_D0:STD_LOGIC;
signal	AUTO_CONFIG_CYCLE:STD_LOGIC;
signal	IDE_CYCLE:STD_LOGIC;
signal	AUTO_CONFIG_PAUSE:STD_LOGIC;
begin
	--internal signals	
	RAM2MB		<= '1' 	when 
									A(31 downto 21) = (x"00" & BASEADR)
									AND SHUT_UP(0) ='0' 
						else '0'; -- Adress match and board successfully configured
	RAM4MB		<= '1' 	when 
									A(31 downto 21) = (x"00" & BASEADR_4MB)
									AND SHUT_UP(0) ='0' 
						else '0'; -- Adress match and board successfully configured	
	IDE_SPACE   <= '1'	when 
									A(31 downto 16) = (x"00" & IDE_BASEADR)  
									AND SHUT_UP(1) ='0' 
						else '0'; -- Access to IDE-Space
	AUTO_CONFIG	<= '1'	when 
									A(31 downto 16) = x"00E8"
									AND not (AUTO_CONFIG_DONE ="11")
						else '0'; -- Access to Autoconfig space and internal autoconfig not complete

	--output
	MY_CYCLE		<= '0' 	when (RAM2MB='1' or RAM4MB='1' or AUTO_CONFIG='1' or IDE_SPACE ='1' ) else '1';
	nRAM_SEL 	<= MY_CYCLE; 

	IO4			<= A(2);
	IO5			<= A(3);
		-- this is the clocked process
	ide: process (reset, clk)
	begin
	
		if	(reset = '0') then
			-- reset
			IDE_ENABLE			<='0';
			IDE_R_S		<= '1';
			IDE_W_S		<= '1';
			ROM_OE_S		<= '1';
			IDE_DSACK	<= (others => '1');
			DSACK_16BIT			<= '1';		
		elsif rising_edge(clk) then
			IDE_R_S		<= '1';
			IDE_W_S		<= '1';
			ROM_OE_S	<= '1';
			IDE_DSACK	<= (others => '1');
			DSACK_16BIT			<= '1';		
			if(IDE_SPACE='1' and nAS = '0')then
				if(RW='0')then
					--enable IDE on the first write on this IO-space!
					IDE_ENABLE<='1';
				end if;

				if(RW='0' and IDE_WAIT ='1')then
					--the write goes to the hdd!
					IDE_W_S		<= '0';
					IDE_R_S		<= '1';
					ROM_OE_S		<=	'1';
					if(IDE_WAIT ='1')then --IDE I/O
						DSACK_16BIT		<=	IDE_DSACK(IDE_WAITS);
					end if;
				elsif(RW='1' and IDE_ENABLE='1')then
						--read from IDE instead from ROM
					IDE_W_S		<= '1';
					IDE_R_S		<= '0';
					ROM_OE_S		<=	'1';
					if(IDE_WAIT ='1')then --IDE I/O
						DSACK_16BIT		<=	IDE_DSACK(IDE_WAITS);
					end if;
				elsif(RW='1' and IDE_ENABLE='0')then
					DSACK_16BIT		<= IDE_DSACK(ROM_WAITS);				
					IDE_W_S		<= '1';
					IDE_R_S		<= '1';
					ROM_OE_S		<=	'0';						
				end if;
				
				--generate IO-delay
				IDE_DSACK(0)<='0';
				IDE_DSACK(IDE_DELAY downto 1)		<=	IDE_DSACK(IDE_DELAY-1 downto 0);
			end if;							
		end if;
	end process ide;

	--map signals
	IDE_CS(0)<= not(A(12));			
	IDE_CS(1)<= not(A(13));
	IDE_A(0)	<= A(9);
	IDE_A(1)	<= A(10);
	IDE_A(2)	<= A(11);
	IDE_DIR	<= IDE_R_S;
	IDE_R		<= IDE_R_S;
	IDE_W		<= IDE_W_S;
	ROM_EN	<= IDE_ENABLE;
	ROM_WE	<= '1';
	ROM_OE	<= ROM_OE_S;

	--now decode the adresslines A[0..1] and SIZ[0..1] to determine the ram bank to write
	-- bits 0-7
	BYTE(0)	<= '0' when (RW='1' or ( RW='0' and (	 SIZ="00" or 
														(A(0)='1' and A(1)='1') or 
														(A(1)='1' and SIZ(1)='1') or
														(A(0)='1' and SIZ="11" ))))
								--and nAS ='0'
					 else '1';
	-- bits 8-15
	BYTE(1)	<= '0' when (RW='1' or ( RW='0' and (	(A(0)='0' and A(1)='1') or
														(A(0)='1' and A(1)='0' and SIZ(0)='0') or
														(A(1)='0' and SIZ="11") or 
														(A(1)='0' and SIZ="00"))))
								--and nAS ='0'
					 else '1';
	--bits 16-23
	BYTE(2)	<= '0' when (RW='1' or ( RW='0' and (	(A(0)='1' and A(1)='0') or
														(A(1)='0' and SIZ(0)='0') or 
														(A(1)='0' and SIZ(1)='1'))))
								--and nAS ='0'
					 else '1';
	--bits 24--31
	BYTE(3)	<= '0' when (RW='1' or ( RW='0' and (	A(0)='0' and A(1)='0') ))
								--and nAS ='0'
					 else '1';
	
	--map DSACK signal
	DSACK		<= 	"ZZ" when MY_CYCLE ='1' ELSE
						"01" when DSACK_16BIT	 ='0' else 						
						"01" when AUTO_CONFIG_D0='1' else 
						"11";

	STERM <=  DSACK_32BIT(RAM_WAITS);

	
	OE(0) <= '0' when RAM2MB = '1' and RW = '1' and nAS ='0' else '1';
	OE(1) <= '0' when RAM4MB = '1' and RW = '1' and nAS ='0' else '1';
	WE(0) <= '0' when RAM2MB = '1' and RW = '0' and nAS ='0' else '1';
	WE(1) <= '0' when RAM4MB = '1' and RW = '0' and nAS ='0' else '1';
	INT2	<= '1';

	dsack_gen: process (nAS, clk)
	begin
		if	nAS = '1' then
			AUTO_CONFIG_CYCLE <= '1';
			IDE_CYCLE <='1';
			DSACK_32BIT	<= (others =>'1');
		elsif rising_edge(clk) then -- no reset, so wait for rising edge of the clock, Attention: The memory is triggered at the falling edge, so i can save one register!
			DSACK_32BIT(RAM_DELAY downto 1) <= DSACK_32BIT(RAM_DELAY-1 downto 0);				
			
			if(RAM2MB ='1' or RAM4MB='1')then			
				DSACK_32BIT(0)	<= '0';				
			end if;
			if(AUTO_CONFIG = '1')then
				AUTO_CONFIG_CYCLE <= '0';
			end if;
			if(IDE_SPACE = '1')then
				IDE_CYCLE <= '0';
			end if;
		end if;
	end process dsack_gen;
	
	--enable caching for RAM
	CIIN	<= '1' when DSACK_32BIT(0) ='0' else 
				'0' when AUTO_CONFIG_CYCLE='0' or IDE_CYCLE ='0' else
				'Z';


	D	<=	-- when RW='0' or AUTO_CONFIG ='0' else
			Dout1	 when RW='1' and nAS='0' and AUTO_CONFIG_CYCLE ='0' else
			"ZZZZ";


	autoconfig: process (reset, clk)
	begin
		if	reset = '0' then
			-- reset active ...
			Dout1<="1111";
			SHUT_UP	<="11";
			BASEADR <="111";
			BASEADR_4MB <="111";
			IDE_BASEADR<=x"FF";
			AUTO_CONFIG_D0 <= '0';
			nAS_D0 <='1';
			
			AUTO_CONFIG_PAUSE <='0';
			AUTO_CONFIG_DONE_CYCLE	<="00";
			AUTO_CONFIG_DONE	<="00";
			
			--use these presets for CDTV: This makes the DMAC config first!
			--AUTO_CONFIG_PAUSE <='1';
			--AUTO_CONFIG_DONE_CYCLE	<="11";
			--AUTO_CONFIG_DONE	<="11";
			
			

		elsif rising_edge(clk) then -- no reset, so wait for rising edge of the clock		

			nAS_D0				<=nAS;

			-- wait one autoconfig-strobe for CDTV!
			if( 	A(31 downto 16) = x"00E8" and A (6 downto 1)="100100" --correct address
					and RW='0' and --write
					nAS_D0='0' and nAS ='1' --end of cycle
					and AUTO_CONFIG_PAUSE ='1') then --pause enabled
				AUTO_CONFIG_PAUSE <='0';
				AUTO_CONFIG_DONE_CYCLE	<="00";
				AUTO_CONFIG_DONE <= "00";
			end if;
			
			
			if(nAS='1' and nAS_D0='0' and AUTO_CONFIG_D0= '1')then
				AUTO_CONFIG_DONE <= AUTO_CONFIG_DONE_CYCLE;
			end if;
			
			--default values (will be ovewritten later)
			Dout1<="1111";
			AUTO_CONFIG_D0 <='0';
			
			if(AUTO_CONFIG= '1' and nAS='0') then
				AUTO_CONFIG_D0 <='1';
				case A(6 downto 1) is
					when "000000"	=> if(AUTO_CONFIG_DONE(0)='0')then
												Dout1 <= 	"1110" ; --ZII, System-Memory, no ROM
											else
												Dout1 <= 	"1101" ; --ZII, no Memory,  ROM
											end if;
					when "000001"	=> if(AUTO_CONFIG_DONE(0)='0')then
												Dout1 <=	"0111" ; --one Card, 4MB = 111
											else
												Dout1 <=	"0001" ; --one Card, 64kb = 001
											end if;
					when "000011"	=> if(AUTO_CONFIG_DONE(0)='0')then
												Dout1 <=	"1101" ; --ProductID low nibble: F->0000
											else
												Dout1 <=	"1001" ; --ProductID low nibble: 9->0110=6
											end if;
					when "001001"	=> if(AUTO_CONFIG_DONE(0)='0')then
												Dout1 <=	"0101" ; --Ventor ID 1
											else
												Dout1 <=	"0111" ; --Ventor ID 1
											end if;
					when "001010"	=> if(AUTO_CONFIG_DONE(0)='0')then
												Dout1 <=	"1110" ; --Ventor ID 2
											else
												Dout1 <=	"1101" ; --Ventor ID 2
											end if;
					when "001011"	=> 
											Dout1 <=	"0011" ; --Ventor ID 3 : $0A1C: A1K.org
											--Ventor ID 3 2nd board : $082C: BSC
					when "001100"	=> Dout1 <=	"0100" ; --Serial byte 0 (msb) high nibble
					when "001101"	=> Dout1 <=	"1110" ; --Serial byte 0 (msb) low  nibble
					when "001110"	=> Dout1 <=	"1001" ; --Serial byte 1       high nibble
					when "001111"	=> Dout1 <=	"0100" ; --Serial byte 1       low  nibble
					when "010011"	=> 
											Dout1 <=	"1010" ; --Serial byte 3 (lsb) low  nibble: B16B00B5
					when "010111"	=> Dout1 <=	"1110" ; --Rom vector low byte low  nibble
					when "100000"	=> 
											Dout1 <=	"0000" ; --Interrupt config: all zero
					when "100001"	=> 
											Dout1 <=	"0000" ; --Interrupt config: all zero
					when others	=> 	
											Dout1 <=	"1111" ;
				end case;	

				if( RW='0' and nDS='0')then --write
					if(AUTO_CONFIG_DONE(0)='0')then
						if(A (6 downto 1)="100100")then								
							BASEADR 				<= D(3 downto 1); --Base adress
							BASEADR_4MB 		<= D(3 downto 1)+"001"; 
							AUTO_CONFIG_DONE_CYCLE(0)	<='1'; --done here
							SHUT_UP(0)				<='0'; --enable board
						elsif(A (6 downto 1)="100110")then
							AUTO_CONFIG_DONE_CYCLE(0)	<='1'; --done here
						end if;
					elsif(AUTO_CONFIG_DONE(1)='0')then
						if(A (6 downto 1)="100100")then
							IDE_BASEADR(7 downto 4)	<= D(3 downto 0); --Base adress
							SHUT_UP(1) <= '0'; --enable board
							AUTO_CONFIG_DONE_CYCLE(1)	<='1'; --done here
						elsif(A (6 downto 1)="100101")then
							IDE_BASEADR(3 downto 0)	<= D(3 downto 0); --Base adress
						elsif(A (6 downto 1)="100110")then
							AUTO_CONFIG_DONE_CYCLE(1)	<='1'; --done here
						end if;
					end if;
				end if;
			end if;
		end if;

	end process autoconfig; --- that's all
end Behavioral;
