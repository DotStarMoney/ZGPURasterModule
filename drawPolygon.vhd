
library ieee;                                   
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity drawPolygon is
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
end drawPolygon;

architecture behv of drawPolygon is
	
	constant UFEI_BITS : integer := UFEI_EXPONENT + UFEI_MANTISSA;

	type draw_state is (init, prep_hi, draw_hi, adjust_lo, prep_lo, draw_lo, complete);
	type sign is (z, p, n);
	
	signal ufei_OneHalf : signed(UFEI_BITS-1 downto 0) := to_signed(2**(UFEI_EXPONENT - 1), UFEI_BITS);
	signal ufei_One : signed(UFEI_BITS-1 downto 0) := to_signed(2**UFEI_EXPONENT, UFEI_BITS);	
	
	signal delta_x0, delta_y0: signed(UFEI_BITS-1 downto 0);
	signal delta_x1, delta_y1: signed(UFEI_BITS-1 downto 0);
	signal delta_x2, delta_y2: signed(UFEI_BITS-1 downto 0);
			
	signal x0, y0: signed(UFEI_BITS-1 downto 0);
	signal x1, y1: signed(UFEI_BITS-1 downto 0);
	--signal x2: signed(UFEI_BITS-1 downto 0);
	signal y2: signed(UFEI_BITS-1 downto 0);
	
	signal xrdy: signed(UFEI_BITS-1 downto 0);
	signal xldy: signed(UFEI_BITS-1 downto 0);
	signal xm_r: signed(UFEI_BITS-1 downto 0);
	signal xm_l: signed(UFEI_BITS-1 downto 0);
	signal xlimit_r: signed(UFEI_BITS-1 downto 0);
	signal xlimit_l: signed(UFEI_BITS-1 downto 0);
	signal xscan_rs: signed(UFEI_BITS-1 downto 0);
	signal xscan_ls: signed(UFEI_BITS-1 downto 0);	
	
	signal yscan: signed(UFEI_BITS-1 downto 0);
	
	signal x0_base0: signed(UFEI_BITS-1 downto 0);
	signal x0_base2: signed(UFEI_BITS-1 downto 0);
	--signal x1_base1: signed(UFEI_BITS-1 downto 0);
	
	signal sided: std_logic;
	
	signal fill_op: std_logic;
	signal xscan: signed(UFEI_MANTISSA-1 downto 0);
	signal xlimit: signed(UFEI_MANTISSA-1 downto 0);
			
	signal sn0, sn1, sn2: sign;
				
	signal op_state: draw_state;
	
	begin
		process(clk)
			variable c_delta_x0, c_delta_y0: signed(UFEI_BITS-1 downto 0);
			variable c_delta_x1, c_delta_y1: signed(UFEI_BITS-1 downto 0);
			variable c_delta_x2, c_delta_y2: signed(UFEI_BITS-1 downto 0);
		
			variable c_x0_base0: signed(UFEI_BITS-1 downto 0);
			variable c_x0_base2: signed(UFEI_BITS-1 downto 0);
			variable c_x1_base1: signed(UFEI_BITS-1 downto 0);
			
			variable c_x0, c_y0: signed(UFEI_BITS-1 downto 0);
			variable c_x1, c_y1: signed(UFEI_BITS-1 downto 0);
			variable c_x2, c_y2: signed(UFEI_BITS-1 downto 0);
			variable temp_swap : signed(UFEI_BITS-1 downto 0);
			
			variable adjust : signed(UFEI_EXPONENT downto 0);
			variable b_slice: signed(UFEI_EXPONENT downto 0);
			variable s_frac : signed(UFEI_EXPONENT downto 0);
			variable s_frac_inv : signed(UFEI_EXPONENT downto 0);
			variable start_flip : signed (UFEI_BITS-1 downto 0);
			variable mant_slice1: signed (UFEI_MANTISSA-1 downto 0);
			variable mant_slice2: signed (UFEI_MANTISSA-1 downto 0);
			variable full_adjust: signed (UFEI_BITS-1 downto 0);
			
			variable mult1: signed(2*UFEI_BITS-1 downto 0);
			variable mult2: signed(2*UFEI_BITS-1 downto 0);
				
			variable multNoExp1: signed((UFEI_BITS + UFEI_MANTISSA)-1 downto 0);
			variable multReduce1: signed(UFEI_BITS-1 downto 0);
			variable multReduce2: signed(UFEI_BITS-1 downto 0);
			
			variable pset_loc: signed((VIDEO_WIDTH_BITS + UFEI_MANTISSA) downto 0);
		
			variable left_complete: std_logic;
			variable right_complete: std_logic;
		
			begin
				if(clk'event and clk = '1') then
					if(rst = '1') then
						op_state <= init;
						draw_strb <= '0';
						draw_complete <= '0';
					else
						case op_state is
							when init =>
							
								c_x0 := p_x0 + ufei_OneHalf;
								c_y0 := p_y0 + ufei_OneHalf;
								c_x1 := p_x1 + ufei_OneHalf;
								c_y1 := p_y1 + ufei_OneHalf;
								c_x2 := p_x2 + ufei_OneHalf;
								c_y2 := p_y2 + ufei_OneHalf;
								
								if c_y1 > c_y2 then
									temp_swap := c_y1;
									c_y1 := c_y2;
									c_y2 := temp_swap;
									
									temp_swap := c_x1;
									c_x1 := c_x2;
									c_x2 := temp_swap;
								end if;
								
								if c_y0 > c_y1 then
									temp_swap := c_y0;
									c_y0 := c_y1;
									c_y1 := temp_swap;
									
									temp_swap := c_x0;
									c_x0 := c_x1;
									c_x1 := temp_swap;
								end if;
								
								if c_y1 > c_y2 then
									temp_swap := c_y1;
									c_y1 := c_y2;
									c_y2 := temp_swap;
									
									temp_swap := c_x1;
									c_x1 := c_x2;
									c_x2 := temp_swap;
								end if;
							
								c_delta_x0 := c_x1 - c_x0;
								c_delta_y0 := c_y1 - c_y0;
								if c_delta_x0 > 0 then
									sn0 <= p;
								elsif c_delta_x0 < 0 then
									sn0 <= n;
								else
									sn0 <= z;
								end if;
								
								c_delta_x1 := c_x2 - c_x1;
								c_delta_y1 := c_y2 - c_y1;
								if c_delta_x1 > 0 then
									sn1 <= p;
								elsif c_delta_x1 < 0 then
									sn1 <= n;
								else
									sn1 <= z;
								end if;
								
								c_delta_x2 := c_x2 - c_x0;
								c_delta_y2 := c_y2 - c_y0;
								if c_delta_x2 > 0 then
									sn2 <= p;
								elsif c_delta_x2 < 0 then
									sn2 <= n;
								else
									sn2 <= z;
								end if;
								
								mult1 := c_delta_x0 * c_delta_y1;
								multReduce1 := shift_right(mult1, UFEI_EXPONENT)(UFEI_BITS-1 downto 0);
								mult2 := c_delta_y0 * c_delta_x1;
								multReduce2 := shift_right(mult2, UFEI_EXPONENT)(UFEI_BITS-1 downto 0);
								if multReduce1 - multReduce2 < 0 then
									sided <= '0';
								else
									sided <= '1';
								end if;
								
								delta_x0 <= abs c_delta_x0;
								delta_x1 <= abs c_delta_x1;
								delta_x2 <= abs c_delta_x2;
								
								delta_y0 <= c_delta_y0;
								delta_y1 <= c_delta_y1;
								delta_y2 <= c_delta_y2;
								
								x0 <= c_x0;
								y0 <= c_y0;
								x1 <= c_x1;
								y1 <= c_y1;
								--x2 <= c_x2;
								y2 <= c_y2;
								
								op_state <= prep_hi;
								
								draw_complete <= '0';
								draw_strb <= '0';
								
						when prep_hi =>
						
								b_slice := ufei_One(UFEI_EXPONENT downto 0) - 
											  ('0' & x0(UFEI_EXPONENT-1 downto 0));
								start_flip := x0(UFEI_BITS-1 downto UFEI_EXPONENT) & b_slice(UFEI_EXPONENT-1 downto 0);
							
								b_slice := ufei_One(UFEI_EXPONENT downto 0) - 
											  ('0' & y0(UFEI_EXPONENT-1 downto 0));
								s_frac_inv := '0' & b_slice(UFEI_EXPONENT-1 downto 0);
								
								s_frac := -('0' & y0(UFEI_EXPONENT-1 downto 0));
						
								mant_slice1 := shift_right(x0, UFEI_EXPONENT)(UFEI_MANTISSA-1 downto 0) + 1;
								
								-------- RIGHT side------
								if sn0 = p then
									c_x0_base0 := x0;
								else
									c_x0_base0 := start_flip;
								end if;
		
								if ((sn0 = p) and (sided = '1')) or ((sn0 = n) and (sided = '0')) then
									adjust := s_frac_inv;
								else
									adjust := s_frac;
								end if;
								mult1 := c_x0_base0 * delta_y0;
								multReduce1 := shift_right(mult1, UFEI_EXPONENT)(UFEI_BITS-1 downto 0);
								mult2 := resize(adjust * delta_x0, mult2'length);
								multReduce2 := shift_right(mult2, UFEI_EXPONENT)(UFEI_BITS-1 downto 0);
								xrdy <= multReduce1 + multReduce2;
								
								multNoExp1 := mant_slice1 * delta_y0;
								xm_r <= multNoExp1(UFEI_BITS-1 downto 0);
								
								mult1 := (c_x0_base0 + delta_x0) * delta_y0;
								xlimit_r <= shift_right(mult1, UFEI_EXPONENT)(UFEI_BITS-1 downto 0);
								-- will this take new value of x0_base0?
								xscan_rs <= c_x0_base0;
								x0_base0 <= c_x0_base0;
								
								-- ------------ do LEFT side
								if sn2 = p then
									c_x0_base2 := x0;
								else
									c_x0_base2 := start_flip;
								end if;
		
								if ((sn2 = p) and (sided = '1')) or ((sn2 = n) and (sided = '0')) then
									adjust := s_frac;
								else
									adjust := s_frac_inv;
								end if;
								mult1 := c_x0_base2 * delta_y2;
								multReduce1 := shift_right(mult1, UFEI_EXPONENT)(UFEI_BITS-1 downto 0);
								mult2 := resize(adjust * delta_x2, mult2'length);
								multReduce2 := shift_right(mult2, UFEI_EXPONENT)(UFEI_BITS-1 downto 0);
								xldy <= multReduce1 + multReduce2;
								
								multNoExp1 := mant_slice1 * delta_y2;
								xm_l <= multNoExp1(UFEI_BITS-1 downto 0);
								
								mult2 := delta_y0 * delta_x2;
								multReduce2 := shift_right(mult2, UFEI_EXPONENT)(UFEI_BITS-1 downto 0);
								xlimit_l <= multReduce1 + multReduce2;
								
								xscan_ls <= c_x0_base2;
								x0_base2 <= c_x0_base2;
								
								yscan <= y0;
								
								fill_op <= '0';
								op_state <= draw_hi;
						when draw_hi =>
								mant_slice1 := yscan(UFEI_BITS-1 downto UFEI_EXPONENT);
								mant_slice2 := y1(UFEI_BITS-1 downto UFEI_EXPONENT);
								if fill_op = '0' then
									if mant_slice1 < mant_slice2 then
										if (xm_r < xrdy) and (xm_r < xlimit_r) then
											xm_r <= xm_r + delta_y0;
											case sn0 is
												when p => xscan_rs <= xscan_rs + ufei_One;
												when n => xscan_rs <= xscan_rs - ufei_One;
												when z => xscan_rs <= xscan_rs;
											end case;
											right_complete := '0';
										else
											right_complete := '1';
										end if;
										
										if (xm_l < xldy) and (xm_l < xlimit_l) then
											xm_l <= xm_l + delta_y2;
											case sn2 is
												when p => xscan_ls <= xscan_ls + ufei_One;
												when n => xscan_ls <= xscan_ls - ufei_One;
												when z => xscan_ls <= xscan_ls;
											end case;
											left_complete := '0';
										else
											left_complete := '1';
										end if;
										
										if (left_complete = '1') and (right_complete = '1') then
											fill_op <= '1';
											if sided = '0' then
												xscan  <= xscan_rs(UFEI_BITS-1 downto UFEI_EXPONENT);
												xlimit <= xscan_ls(UFEI_BITS-1 downto UFEI_EXPONENT);
											else
												xscan  <= xscan_ls(UFEI_BITS-1 downto UFEI_EXPONENT);
												xlimit <= xscan_rs(UFEI_BITS-1 downto UFEI_EXPONENT);
											end if;
										end if;
									else
										op_state <= adjust_lo;
									end if;
								else
									if xscan <= xlimit then
									  pset_loc := mant_slice1 * to_signed(VIDEO_WIDTH, VIDEO_WIDTH_BITS+1) + xscan;
										draw_addr <= std_logic_vector(pset_loc(VIDEO_SIZE_BITS-1 downto 0));
										draw_data <= col;
										draw_strb <= '1';
										
										xscan <= xscan + 1;
									else
										draw_strb <= '0';
										yscan <= yscan + ufei_One;
										xrdy <= xrdy + delta_x0;
										xldy <= xldy + delta_x2;
										fill_op <= '0';
									end if;
								end if;
						when adjust_lo =>
								if y0 /= y1 then
									if (xm_r < xrdy) and (xm_r <= xlimit_r) then
										xm_r <= xm_r + delta_y0;
										case sn0 is
											when p => xscan_rs <= xscan_rs + ufei_One;
											when n => xscan_rs <= xscan_rs - ufei_One;
											when z => xscan_rs <= xscan_rs;
										end case;
									else
										op_state <= prep_lo;
									end if;
								else
									xscan_rs <= x1;
									xscan_ls <= x0;
									op_state <= prep_lo;
								end if;
						when prep_lo =>
								mult1 := (x0_base2 + delta_x2) * delta_y2;
								xlimit_l <= shift_right(mult1, UFEI_EXPONENT)(UFEI_BITS-1 downto 0);
								
								if sn1 = p then
									c_x1_base1 := x1;
								else
									b_slice := ufei_One(UFEI_EXPONENT downto 0) - 
											  ('0' & x1(UFEI_EXPONENT-1 downto 0));
									c_x1_base1 := x1(UFEI_BITS-1 downto UFEI_EXPONENT) & b_slice(UFEI_EXPONENT-1 downto 0);
								end if;
								if ((sn1 = p) and (sided = '1')) or ((sn1 = n) and (sided = '0')) then
									b_slice := ufei_One(UFEI_EXPONENT downto 0) - 
												 ('0' & y1(UFEI_EXPONENT-1 downto 0));
									adjust := '0' & b_slice(UFEI_EXPONENT-1 downto 0);		
								else
									adjust := -('0' & y1(UFEI_EXPONENT-1 downto 0));
								end if;
								mult1 := c_x1_base1 * delta_y1;
								multReduce1 := shift_right(mult1, UFEI_EXPONENT)(UFEI_BITS-1 downto 0);
								mult2 := resize(adjust * delta_x1, mult2'length);
								multReduce2 := shift_right(mult2, UFEI_EXPONENT)(UFEI_BITS-1 downto 0);
								xrdy <= multReduce1 + multReduce2;
								
								if (sn1 = n) and (sn0 = n) then
									full_adjust := (c_x1_base1 - delta_x0) + (abs (xscan_rs - x0_base0));
								elsif y1 /= y0 then
									full_adjust := xscan_rs;
								else
									full_adjust := x1;
								end if;
								mant_slice1 := full_adjust(UFEI_BITS-1 downto UFEI_EXPONENT) + 1;
								multNoExp1 := mant_slice1 * delta_y1;
								xm_r <= multNoExp1(UFEI_BITS-1 downto 0);
								
								mult1 := (c_x1_base1 + delta_x1) * delta_y1;
								xlimit_r <= shift_right(mult1, UFEI_EXPONENT)(UFEI_BITS-1 downto 0);
								--x1_base1 <= c_x1_base1
								
								fill_op <= '0';
								op_state <= draw_lo;
						when draw_lo =>
								mant_slice1 := yscan(UFEI_BITS-1 downto UFEI_EXPONENT);
								mant_slice2 := y2(UFEI_BITS-1 downto UFEI_EXPONENT);
								if fill_op = '0' then
									if mant_slice1 <= mant_slice2 then
										if (xm_r < xrdy) and (xm_r < xlimit_r) then
											xm_r <= xm_r + delta_y1;
											case sn1 is
												when p => xscan_rs <= xscan_rs + ufei_One;
												when n => xscan_rs <= xscan_rs - ufei_One;
												when z => xscan_rs <= xscan_rs;
											end case;
											right_complete := '0';
										else
											right_complete := '1';
										end if;
										
										if (xm_l < xldy) and (xm_l < xlimit_l) then
											xm_l <= xm_l + delta_y2;
											case sn2 is
												when p => xscan_ls <= xscan_ls + ufei_One;
												when n => xscan_ls <= xscan_ls - ufei_One;
												when z => xscan_ls <= xscan_ls;
											end case;
											left_complete := '0';
										else
											left_complete := '1';
										end if;
										
										if (left_complete = '1') and (right_complete = '1') then
											fill_op <= '1';
											if sided = '0' then
												xscan  <= xscan_rs(UFEI_BITS-1 downto UFEI_EXPONENT);
												xlimit <= xscan_ls(UFEI_BITS-1 downto UFEI_EXPONENT);
											else
												xscan  <= xscan_ls(UFEI_BITS-1 downto UFEI_EXPONENT);
												xlimit <= xscan_rs(UFEI_BITS-1 downto UFEI_EXPONENT);
											end if;
										end if;
									else
										op_state <= complete;
									end if;
								else
									if xscan <= xlimit then
									  pset_loc := mant_slice1 * to_signed(VIDEO_WIDTH, VIDEO_WIDTH_BITS+1) + xscan;
										draw_addr <= std_logic_vector(pset_loc(VIDEO_SIZE_BITS-1 downto 0));
										draw_data <= col;
										draw_strb <= '1';
										
										xscan <= xscan + 1;
									else
										draw_strb <= '0';
										yscan <= yscan + ufei_One;
										xrdy <= xrdy + delta_x1;
										xldy <= xldy + delta_x2;
										fill_op <= '0';
									end if;
								end if;
						when complete =>
							-- output some complete signal
							draw_complete <= '1';
						end case;
					end if;
				end if;
		end process;

end behv;

