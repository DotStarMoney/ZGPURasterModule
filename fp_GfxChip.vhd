
library ieee;                                   
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fp_GfxChip is
	port(
		rst : in std_logic;
		clk : in std_logic;
		
		mode : in std_logic;
	
		VGA_R 		: out std_logic_vector(7 downto 0);
		VGA_G 		: out std_logic_vector(7 downto 0);
		VGA_B 		: out std_logic_vector(7 downto 0);
		VGA_BLANK_N : out std_logic;
		VGA_SYNC_N  : out std_logic; 
		VGA_HS      : out std_logic;
		VGA_VS      : out std_logic;
		VGA_CLK     : out std_logic
	);
end fp_GfxChip;

architecture behv of fp_GfxChip is
	
	component VGA_Controller is
		port(
			rst   : in std_logic;
			clk   : in std_logic;
					
			gfx_wren : in std_logic;
			gfx_data : in std_logic_vector(11 downto 0);
			gfx_addr : in std_logic_vector(16 downto 0);

			flip_req : in std_logic;
			flip_ack : out std_logic;
			
			VGA_R 		: out std_logic_vector(7 downto 0);
			VGA_G 		: out std_logic_vector(7 downto 0);
			VGA_B 		: out std_logic_vector(7 downto 0);
			VGA_BLANK_N : out std_logic;
			VGA_SYNC_N  : out std_logic; 
			VGA_HS      : out std_logic;
			VGA_VS      : out std_logic;
			VGA_CLK     : out std_logic
		);
	end component;
	component drawPolygon is
		generic(
			UFEI_MANTISSA    : natural := 18;
			UFEI_EXPONENT    : natural := 8;
			VIDEO_WIDTH_BITS : natural := 9;
			VIDEO_WIDTH      : natural := 320;
			VIDEO_SIZE_BITS  : natural := 17
		);
		port(
			clk : in std_logic;
			rst : in std_logic;
			
			p_x0 : in signed(UFEI_MANTISSA+UFEI_EXPONENT-1 downto 0);
			p_y0 : in signed(UFEI_MANTISSA+UFEI_EXPONENT-1 downto 0);
			p_x1 : in signed(UFEI_MANTISSA+UFEI_EXPONENT-1 downto 0);
			p_y1 : in signed(UFEI_MANTISSA+UFEI_EXPONENT-1 downto 0);
			p_x2 : in signed(UFEI_MANTISSA+UFEI_EXPONENT-1 downto 0);
			p_y2 : in signed(UFEI_MANTISSA+UFEI_EXPONENT-1 downto 0);
			
			col : in std_logic_vector(11 downto 0);
			
			draw_addr : out std_logic_vector(VIDEO_SIZE_BITS-1 downto 0);
			draw_data : out std_logic_vector(11 downto 0);
			draw_strb : out std_logic;
			
			draw_complete : out std_logic
		);
	end component;
	component ANIM_DATA is
		port(
			address : in std_logic_vector (8 downto 0);
			clock	  : in std_logic;
			q		  : out std_logic_vector (493 downto 0)
		);
	end component;

	constant UFEI_BITS : integer := 26;
	constant video_size : integer := 76800;
	constant clr_color : std_logic_vector(11 downto 0) := "000000000001";
	
	type render_stage is (clear, draw_triangles, stall);

	signal stage : render_stage;
	signal clear_pxl : integer range 0 to 76799;
	
	signal data_source : std_logic;
	
	signal tri_data : std_logic_vector(11 downto 0);
	signal tri_addr : std_logic_vector(16 downto 0);
	signal clr_data : std_logic_vector(11 downto 0);
	signal clr_addr : std_logic_vector(16 downto 0);
	signal pxl_data : std_logic_vector(11 downto 0);
	signal pxl_addr : std_logic_vector(16 downto 0);
	
	signal page_write : std_logic;
	signal refresh_ack : std_logic;
	signal refresh : std_logic;
	
	signal anim_block_data : std_logic_vector(493 downto 0);
	signal anim_block_addr : unsigned(8 downto 0);
	
	signal current_quad : integer range 0 to 6;
	signal poly_col: std_logic_vector(11 downto 0);
	signal x0, y0: std_logic_vector(UFEI_BITS-1 downto 0);
	signal x1, y1: std_logic_vector(UFEI_BITS-1 downto 0);
	signal x2, y2: std_logic_vector(UFEI_BITS-1 downto 0);
	
	signal reset_draw : std_logic;
	signal draw_bit : std_logic;
	signal draw_complete : std_logic;
	signal half_complete : std_logic;
	signal mask_draw : std_logic;

	begin
	
		-- format of anim ROM (360 locations):
		--     26bits p0_x, 26bits p0_y
		--     26bits p1_x, 26bits p1_y
		--     26bits p2_x, 26bits p2_y
		--     26bits p3_x, 26bits p3_y
		--     26bits p4_x, 26bits p4_y
		--     26bits p5_x, 26bits p5_y
		--     26bits p6_x, 26bits p6_y
		--     26bits p7_x, 26bits p7_y
		--     12bits col0
		--     12bits col1
		--     12bits col2
		--     12bits col3
		--     12bits col4S
		--     12bits col5
		--     6bits  visibility
		
	
		rom0 : ANIM_DATA port map(std_logic_vector(anim_block_addr), clk, anim_block_data);
	
		vga0 : VGA_Controller port map(rst, clk, page_write, pxl_data, pxl_addr, refresh, refresh_ack, 
												 VGA_R, VGA_G, VGA_B,
												 VGA_BLANK_N, VGA_SYNC_N,
												 VGA_HS, VGA_VS,
												 VGA_CLK);
		draw0 : drawPolygon port map(clk, reset_draw, 
												  signed(x0), signed(y0),
									   	     signed(x1), signed(y1), 
												  signed(x2), signed(y2), 
												  poly_col, 
												  tri_addr, tri_data, 
												  draw_bit, draw_complete);
												 
		pxl_data <= clr_data when (data_source = '0') else tri_data;
		pxl_addr <= clr_addr when (data_source = '0') else tri_addr;

		process(clk, rst)
			begin
				if rst='1' then
					stage <= clear;
					clear_pxl <= 0;
					data_source <= '0';
					anim_block_addr <= to_unsigned(0, anim_block_addr'length); -- buffer up first data block
					reset_draw <= '1';
					refresh <= '0';
				else
					if clk'event and (clk='1') then
						case stage is
							when clear =>
								if clear_pxl /= (video_size - 1) then
									clear_pxl <= clear_pxl + 1;
									page_write <= '1';
									clr_addr <= std_logic_vector(to_unsigned(clear_pxl, 17));
									clr_data <= clr_color;
								else
									stage <= draw_triangles;
									page_write <= '0';
									current_quad <= 0;
									half_complete <= '0';
									reset_draw <= '1'; --one cycle reset
									mask_draw <= '0';
								end if;
							when draw_triangles =>
									page_write <= draw_bit;
									data_source <= '1';
									
									case current_quad is
										when 0 =>
										
											if anim_block_data(0) = '0' then
												poly_col <= anim_block_data(77 downto 66);
												if half_complete = '0' then
													x0 <= anim_block_data(493 downto 468);
													y0 <= anim_block_data(467 downto 442);
													
													x1 <= anim_block_data(441 downto 416);
													y1 <= anim_block_data(415 downto 390);
													
													x2 <= anim_block_data(389 downto 364);
													y2 <= anim_block_data(363 downto 338);
													if (draw_complete and mask_draw) = '1' then 
														half_complete <= '1';
														reset_draw <= '1';
														mask_draw <= '0';
													else
														reset_draw <= '0';
													  mask_draw <= '1';
													end if;
												else
													x0 <= anim_block_data(441 downto 416);
													y0 <= anim_block_data(415 downto 390);
													
													x1 <= anim_block_data(337 downto 312);
													y1 <= anim_block_data(311 downto 286);
													
													x2 <= anim_block_data(389 downto 364);
													y2 <= anim_block_data(363 downto 338);
													if (draw_complete and mask_draw) = '1' then 
														half_complete <= '0';
														current_quad <= current_quad + 1;
														reset_draw <= '1';
														mask_draw <= '0';
													else
														reset_draw <= '0';
														mask_draw <= '1';
													end if;
												end if;	
											else
												current_quad <= current_quad + 1;
											end if;
											
										when 1 =>
										
											if anim_block_data(1) = '0' then
												poly_col <= anim_block_data(65 downto 54);
												if half_complete = '0' then
													x0 <= anim_block_data(233 downto 208);
													y0 <= anim_block_data(207 downto 182);
													
													x1 <= anim_block_data(285 downto 260);
													y1 <= anim_block_data(259 downto 234);
													
													x2 <= anim_block_data(129 downto 104);
													y2 <= anim_block_data(103 downto 78);
													if (draw_complete and mask_draw) = '1' then 
														half_complete <= '1';
														reset_draw <= '1';
														mask_draw <= '0';
													else
														reset_draw <= '0';
													  mask_draw <= '1';
													end if;
												else
													x0 <= anim_block_data(285 downto 260);
													y0 <= anim_block_data(259 downto 234);
													
													x1 <= anim_block_data(181 downto 156);
													y1 <= anim_block_data(155 downto 130);
													
													x2 <= anim_block_data(129 downto 104);
													y2 <= anim_block_data(103 downto 78);
													if (draw_complete and mask_draw) = '1' then 
														half_complete <= '0';
														current_quad <= current_quad + 1;
														reset_draw <= '1';
														mask_draw <= '0';
													else
														reset_draw <= '0';
														mask_draw <= '1';
													end if;
												end if;	
											else
												current_quad <= current_quad + 1;
											end if;
										
										when 2 =>
										
											if anim_block_data(2) = '0' then
												poly_col <= anim_block_data(53 downto 42);
												if half_complete = '0' then
													x0 <= anim_block_data(285 downto 260);
													y0 <= anim_block_data(259 downto 234);
													
													x1 <= anim_block_data(493 downto 468);
													y1 <= anim_block_data(467 downto 442);
													
													x2 <= anim_block_data(181 downto 156);
													y2 <= anim_block_data(155 downto 130);
													if (draw_complete and mask_draw) = '1' then 
														half_complete <= '1';
														reset_draw <= '1';
														mask_draw <= '0';
													else
														reset_draw <= '0';
													  mask_draw <= '1';
													end if;
												else
													x0 <= anim_block_data(493 downto 468);
													y0 <= anim_block_data(467 downto 442);
												
													x1 <= anim_block_data(389 downto 364);
													y1 <= anim_block_data(363 downto 338);
													
													x2 <= anim_block_data(181 downto 156);
													y2 <= anim_block_data(155 downto 130);
													if (draw_complete and mask_draw) = '1' then 
														half_complete <= '0';
														current_quad <= current_quad + 1;
														reset_draw <= '1';
														mask_draw <= '0';
													else
														reset_draw <= '0';
														mask_draw <= '1';
													end if;
												end if;	
											else
												current_quad <= current_quad + 1;
											end if;
										
										when 3 =>
										
											if anim_block_data(3) = '0' then
												poly_col <= anim_block_data(41 downto 30);
												if half_complete = '0' then
													x0 <= anim_block_data(441 downto 416);
													y0 <= anim_block_data(415 downto 390);
													
													x1 <= anim_block_data(233 downto 208);
													y1 <= anim_block_data(207 downto 182);
													
													x2 <= anim_block_data(337 downto 312);
													y2 <= anim_block_data(311 downto 286);
													if (draw_complete and mask_draw) = '1' then 
														half_complete <= '1';
														reset_draw <= '1';
														mask_draw <= '0';
													else
														reset_draw <= '0';
													  mask_draw <= '1';
													end if;
												else
													x0 <= anim_block_data(233 downto 208);
													y0 <= anim_block_data(207 downto 182);
													
													x1 <= anim_block_data(129 downto 104);
													y1 <= anim_block_data(103 downto 78);
		
													x2 <= anim_block_data(337 downto 312);
													y2 <= anim_block_data(311 downto 286);
													if (draw_complete and mask_draw) = '1' then 
														half_complete <= '0';
														current_quad <= current_quad + 1;
														reset_draw <= '1';
														mask_draw <= '0';
													else
														reset_draw <= '0';
														mask_draw <= '1';
													end if;
												end if;	
											else
												current_quad <= current_quad + 1;
											end if;
										
										when 4 =>
										
											if anim_block_data(4) = '0' then
												poly_col <= anim_block_data(29 downto 18);
												if half_complete = '0' then
													x0 <= anim_block_data(285 downto 260);
													y0 <= anim_block_data(259 downto 234);
													
													x1 <= anim_block_data(233 downto 208);
													y1 <= anim_block_data(207 downto 182);
													
													x2 <= anim_block_data(493 downto 468);
													y2 <= anim_block_data(467 downto 442);
													if (draw_complete and mask_draw) = '1' then 
														half_complete <= '1';
														reset_draw <= '1';
														mask_draw <= '0';
													else
														reset_draw <= '0';
														mask_draw <= '1';
													end if;
												else
													x0 <= anim_block_data(233 downto 208);
													y0 <= anim_block_data(207 downto 182);
												
													x1 <= anim_block_data(441 downto 416);
													y1 <= anim_block_data(415 downto 390);
													
													x2 <= anim_block_data(493 downto 468);
													y2 <= anim_block_data(467 downto 442);
													if (draw_complete and mask_draw) = '1' then 
														half_complete <= '0';
														current_quad <= current_quad + 1;
														reset_draw <= '1';
														mask_draw <= '0';
													else
														reset_draw <= '0';
														mask_draw <= '1';
													end if;
												end if;	
											else
												current_quad <= current_quad + 1;
											end if;
										
										when 5 =>
										
											if anim_block_data(5) = '0' then
												poly_col <= anim_block_data(17 downto 6);
												if half_complete = '0' then
													x0 <= anim_block_data(389 downto 364);
													y0 <= anim_block_data(363 downto 338);
													
													x1 <= anim_block_data(337 downto 312);
													y1 <= anim_block_data(311 downto 286);
													
													x2 <= anim_block_data(181 downto 156);
													y2 <= anim_block_data(155 downto 130);
													if (draw_complete and mask_draw) = '1' then 
														half_complete <= '1';
														reset_draw <= '1';
														mask_draw <= '0';
													else
														reset_draw <= '0';
														mask_draw <= '1';
													end if;
												else
													x0 <= anim_block_data(337 downto 312);
													y0 <= anim_block_data(311 downto 286);
												
													x1 <= anim_block_data(129 downto 104);
													y1 <= anim_block_data(103 downto 78);
													
													x2 <= anim_block_data(181 downto 156);
													y2 <= anim_block_data(155 downto 130);
													if (draw_complete and mask_draw) = '1' then 
														half_complete <= '0';
														current_quad <= current_quad + 1;
														reset_draw <= '1';
														mask_draw <= '0';
													else
														reset_draw <= '0';
														mask_draw <= '1';
													end if;
												end if;	
											else
												current_quad <= current_quad + 1;
											end if;
										when 6 =>
											refresh <= '1';
											stage <= stall;
									end case;
							when stall =>
								if refresh_ack = '1' then
									refresh <= '0';
									if unsigned(anim_block_addr) /= 359 then
										anim_block_addr <= anim_block_addr + 1;
									else
										anim_block_addr <= to_unsigned(0, anim_block_addr'length);
									end if;
									stage <= clear;
									clear_pxl <= 0;
									data_source <= '0';
								end if;
						end case;
					end if;
				end if;
		end process;
		
		
		
		
		
	
	
end behv;