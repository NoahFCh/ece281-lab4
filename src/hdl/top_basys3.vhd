--+----------------------------------------------------------------------------
--| 
--| COPYRIGHT 2018 United States Air Force Academy All rights reserved.
--| 
--| United States Air Force Academy     __  _______ ___    _________ 
--| Dept of Electrical &               / / / / ___//   |  / ____/   |
--| Computer Engineering              / / / /\__ \/ /| | / /_  / /| |
--| 2354 Fairchild Drive Ste 2F6     / /_/ /___/ / ___ |/ __/ / ___ |
--| USAF Academy, CO 80840           \____//____/_/  |_/_/   /_/  |_|
--| 
--| ---------------------------------------------------------------------------
--|
--| FILENAME      : top_basys3.vhd
--| AUTHOR(S)     : Capt Phillip Warner
--| CREATED       : 3/9/2018  MOdified by Capt Dan Johnson (3/30/2020)
--| DESCRIPTION   : This file implements the top level module for a BASYS 3 to 
--|					drive the Lab 4 Design Project (Advanced Elevator Controller).
--|
--|					Inputs: clk       --> 100 MHz clock from FPGA
--|							btnL      --> Rst Clk
--|							btnR      --> Rst FSM
--|							btnU      --> Rst Master
--|							btnC      --> GO (request floor)
--|							sw(15:12) --> Passenger location (floor select bits)
--| 						sw(3:0)   --> Desired location (floor select bits)
--| 						 - Minumum FUNCTIONALITY ONLY: sw(1) --> up_down, sw(0) --> stop
--|							 
--|					Outputs: led --> indicates elevator movement with sweeping pattern (additional functionality)
--|							   - led(10) --> led(15) = MOVING UP
--|							   - led(5)  --> led(0)  = MOVING DOWN
--|							   - ALL OFF		     = NOT MOVING
--|							 an(3:0)    --> seven-segment display anode active-low enable (AN3 ... AN0)
--|							 seg(6:0)	--> seven-segment display cathodes (CG ... CA.  DP unused)
--|
--| DOCUMENTATION : None
--|
--+----------------------------------------------------------------------------
--|
--| REQUIRED FILES :
--|
--|    Libraries : ieee
--|    Packages  : std_logic_1164, numeric_std
--|    Files     : MooreElevatorController.vhd, clock_divider.vhd, sevenSegDecoder.vhd
--|				   thunderbird_fsm.vhd, sevenSegDecoder, TDM4.vhd, OTHERS???
--|
--+----------------------------------------------------------------------------
--|
--| NAMING CONVENSIONS :
--|
--|    xb_<port name>           = off-chip bidirectional port ( _pads file )
--|    xi_<port name>           = off-chip input port         ( _pads file )
--|    xo_<port name>           = off-chip output port        ( _pads file )
--|    b_<port name>            = on-chip bidirectional port
--|    i_<port name>            = on-chip input port
--|    o_<port name>            = on-chip output port
--|    c_<signal name>          = combinatorial signal
--|    f_<signal name>          = synchronous signal
--|    ff_<signal name>         = pipeline stage (ff_, fff_, etc.)
--|    <signal name>_n          = active low signal
--|    w_<signal name>          = top level wiring signal
--|    g_<generic name>         = generic
--|    k_<constant name>        = constant
--|    v_<variable name>        = variable
--|    sm_<state machine type>  = state machine type definition
--|    s_<signal name>          = state name
--|
--+----------------------------------------------------------------------------
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;


-- Lab 4
entity top_basys3 is
    port(
        -- inputs
        clk     :   in std_logic; -- native 100MHz FPGA clock
        sw      :   in std_logic_vector(15 downto 0);
        btnU    :   in std_logic; -- master_reset
        btnL    :   in std_logic; -- clk_reset
        btnR    :   in std_logic; -- fsm_reset
        
        -- outputs
        led :   out std_logic_vector(15 downto 0);
        -- 7-segment display segments (active-low cathodes)
        seg :   out std_logic_vector(6 downto 0);
        -- 7-segment display active-low enables (anodes)
        an  :   out std_logic_vector(3 downto 0)
    );
end top_basys3;

architecture top_basys3_arch of top_basys3 is 
  
	-- declare components and signals
    component TDM4 is
        generic ( constant k_WIDTH : natural  := 4); 
        Port ( i_clk		: in  STD_LOGIC;
               i_reset      : in  STD_LOGIC; -- asynchronous
               i_D1         : in  STD_LOGIC_VECTOR (k_WIDTH - 1 downto 0);
               i_D0         : in  STD_LOGIC_VECTOR (k_WIDTH - 1 downto 0);
               o_data        : out STD_LOGIC_VECTOR (k_WIDTH - 1 downto 0);
               o_sel        : out STD_LOGIC_VECTOR (3 downto 0)    -- selected data line (one-cold)
        );
     end component TDM4;
     
     component sevenSegDecoder is
        Port ( i_D : in STD_LOGIC_VECTOR (3 downto 0);
                o_S : out STD_LOGIC_VECTOR (6 downto 0)
        );
     end component sevenSegDecoder;
    
    component elevator_controller_fsm is
        Port ( i_clk     : in  STD_LOGIC;
                i_Reset   : in  STD_LOGIC;
                i_stop    : in  STD_LOGIC;
                i_up_down : in  STD_LOGIC;
                o_floor0   : out STD_LOGIC_VECTOR (3 downto 0);
                o_floor1   : out STD_LOGIC_VECTOR (3 downto 0)           
              );
        end component elevator_controller_fsm;
        
    component clock_divider is
        generic ( constant k_DIV : natural := 2	);
        port (  i_clk    : in std_logic;
                i_reset  : in std_logic;           -- asynchronous
                o_clk    : out std_logic           -- divided (slow) clock
        );
        end component clock_divider;
        
    component clock_divider2 is
        generic ( constant k_DIV : natural := 2    );
        port (  i_clk    : in std_logic;
                i_reset  : in std_logic;           -- asynchronous
                o_clk    : out std_logic           -- divided (slow) clock
        );
        end component clock_divider2;
                
        signal w_clk, w_clk2 : std_logic;
        signal w_D0, w_D1, w_D2, w_sel : std_logic_vector(3 downto 0) := (others => '0');
    
begin
	-- PORT MAPS ----------------------------------------
    elevator_controller_fsm_inst : elevator_controller_fsm
        port map(
            i_stop => sw(0),
            i_up_down => sw(1),
            i_Reset => btnR or btnU,           
            i_clk => w_clk2,
            o_floor0 => w_D0,
            o_floor1 => w_D1
        );
        
    clkdiv_inst : clock_divider
            generic map ( k_DIV => 100000 ) -- 1 Hz clock from 100 MHz
                       port map (                          
                           i_clk   => clk,
                           i_reset => btnL or btnU,
                           o_clk   => w_clk
                       ); 
   clkdiv2_inst : clock_divider
           generic map ( k_DIV => 25000000 ) -- 1 Hz clock from 100 MHz
                      port map (                          
                          i_clk   => clk,
                          i_reset => btnL or btnU,
                          o_clk   => w_clk2
                      ); 
 
    sevenSegDecoder_inst : sevenSegDecoder
        port map(
            i_D(0) => w_D2(0),
            i_D(1) => w_D2(1),
            i_D(2) => w_D2(2),
            i_D(3) => w_D2(3),
            o_S(0) => seg(0),
            o_S(1) => seg(1),
            o_S(2) => seg(2),
            o_S(3) => seg(3),
            o_S(4) => seg(4),
            o_S(5) => seg(5),
            o_S(6) => seg(6)

        );
    TDM4_inst : TDM4
        port map(
            i_clk => w_clk,
            i_reset => btnU,
            i_D0 => w_D0,
            i_D1 => w_D1,
            o_data => w_D2,
            o_sel => w_sel
        );
	
	
	-- CONCURRENT STATEMENTS ----------------------------
	
	-- LED 15 gets the FSM slow clock signal. The rest are grounded.
	   led(15) <= w_clk;
	   led(14 downto 0) <= (others => '0');

	-- leave unused switches UNCONNECTED. Ignore any warnings this causes.
	
	-- wire up active-low 7SD anodes (an) as required
    -- Tie any unused anodes to power ('1') to keep them off

	an(3) <= w_sel(0);
	an(2) <= w_sel(1);
	an(1) <= '1';
	an(0) <= '1';
	
end top_basys3_arch;
