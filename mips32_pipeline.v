`timescale 1ns/10ps
module mips_pipeline(input clkP,clkN);

reg[31:0] PC, IF_ID_NPC, IF_ID_IR;
reg[31:0] ID_EX_IR, ID_EX_NPC, ID_EX_A, ID_EX_B, ID_EX_Imm;
reg [31:0] ALUop1, ALUop2;
reg[31:0] EX_MEM_IR, EX_MEM_ALUout, EX_MEM_B;
reg[31:0] MEM_WB_IR, MEM_WB_ALUout, MEM_WB_LMD;
reg[31:0] WB_FETCH_IR,WB_FETCH_type,WB_FETCH_ALUout,WB_FETCH_LMD;
reg[2:0] ID_EX_type, EX_MEM_type, MEM_WB_type;
reg[31:0] Reg_File[31:0];
reg[31:0] Inst_Mem[15:0], Data_Mem[15:0];
reg HALTED;
reg BRANCH_Condition; 
	
parameter ADD=6'b001110, SUB=6'b000001, MUL=6'b000010, OR=6'b000011, AND=6'b000100,
          SLT=6'b000101, LW=6'b000110, SW=6'b000111, ADDI=6'b001000, SUBI=6'b001001,
          SLTI=6'b001010, BEQ=6'b001011, BNEQ=6'b001100, JMP=6'b001101, HLT=6'b111111;
		  
parameter RR_ALU=3'b110, RM_ALU=3'b001, LOAD=3'b010, STORE=3'b011, BRANCH=3'b100, JUMP=3'b101, HALT=3'b111;


// IF STAGE
always@(posedge clkP)
begin

if(HALTED == 0)
begin

// CONDITIONAL BRANCH HAZARD MITIGATION
if(((EX_MEM_IR[31:26] == BNEQ) && (BRANCH_Condition == 0)) || ((EX_MEM_IR[31:26] == BEQ) && (BRANCH_Condition == 1)))
begin
IF_ID_IR <= #3 Inst_Mem[EX_MEM_ALUout];
IF_ID_NPC <= #3 EX_MEM_ALUout + 1;
PC <= #3 EX_MEM_ALUout + 1;
end

// UNCONDITIONAL JUMP HAZARD MITIGATION
else if(IF_ID_IR[31:26] == JMP)
begin
IF_ID_IR <= #3 Inst_Mem[{{6{IF_ID_IR[25]}} , IF_ID_IR[25:0]}];
IF_ID_NPC <= #3 {{6{IF_ID_IR[25]}} , IF_ID_IR[25:0]} +1;
PC <= #3 {{6{IF_ID_IR[25]}} , IF_ID_IR[25:0]} +1;
end

// STALL FOR DATA RAW DEPENDENCY WITH PREVIOUS LOAD INSTRUCTION 
else if((ID_EX_IR[31:26] == LW ) && ((ID_EX_IR[20:16] == IF_ID_IR[25:21]) || (ID_EX_IR[20:16] == IF_ID_IR[20:16])))
begin
IF_ID_IR <= IF_ID_IR;
IF_ID_NPC <= IF_ID_NPC;
PC <= PC;
end

else
begin
IF_ID_IR <= #3 Inst_Mem[PC];
IF_ID_NPC <= #3 PC + 1;
PC <= #3 PC + 1;
end

end
end

// ID STAGE
always@(posedge clkN)
begin

if(HALTED == 0)
begin

// FLUSHING INSTRUCTION FOR CONDITIONAL BRANCH HAZARD MITIGATION
if(((EX_MEM_IR[31:26] == BNEQ) && (BRANCH_Condition == 0)) || ((EX_MEM_IR[31:26] == BEQ) && (BRANCH_Condition == 1)))
begin
ID_EX_A <= #3 0;
ID_EX_B<= #3 0;
ID_EX_IR <= #3 0;
ID_EX_Imm <= #3 0;
ID_EX_NPC <= #3 0;
ID_EX_type <= #3 0;
end

// FLUSHING INSTRUCTION FOR DATA RAW DEPENDENCY WITH PREVIOUS LOAD INSTRUCTION
else if((ID_EX_IR[31:26] == LW ) && ((ID_EX_IR[20:16] == IF_ID_IR[25:21]) || (ID_EX_IR[20:16] == IF_ID_IR[20:16])))
begin
ID_EX_A <= #3 0;
ID_EX_B <= #3 0;
ID_EX_IR <= #3 0;
ID_EX_Imm <= #3 0;
ID_EX_NPC <= #3 0;
ID_EX_type <= #3 0;
end

else 
begin

if(IF_ID_IR[25:21] == 5'b00000)
ID_EX_A <= 0;
else 
ID_EX_A <= #3 Reg_File[IF_ID_IR[25:21]];

if(IF_ID_IR[20:16] == 5'b00000)
ID_EX_B <= 0;
else
ID_EX_B <= #3 Reg_File[IF_ID_IR[20:16]];

ID_EX_IR <= #3 IF_ID_IR;
ID_EX_NPC <= #3 IF_ID_NPC;
ID_EX_Imm <= #3 {{16{IF_ID_IR[15]}}, {IF_ID_IR[15:0]}};

case (IF_ID_IR[31:26])

ADD,SUB,MUL,SLT,AND,OR : ID_EX_type <= #3 RR_ALU;
ADDI,SUBI, SLTI : ID_EX_type <= #3 RM_ALU;
LW : ID_EX_type <= #3 LOAD;
SW : ID_EX_type <= #3 STORE;
BEQ,BNEQ : ID_EX_type <= #3 BRANCH;
JMP : ID_EX_type <= #3 JUMP;
HLT : ID_EX_type <= #3 HALT;

endcase

end

end  
end


// EX STAGE
always@(posedge clkP)
begin

if(HALTED == 0)
begin

// FLUSHING INSTRUCTION FOR CONDITIONAL BRANCH HAZARD MITIGATION
if(((EX_MEM_IR[31:26] == BNEQ) && (BRANCH_Condition == 0)) || ((EX_MEM_IR[31:26] == BEQ) && (BRANCH_Condition == 1)))
begin
EX_MEM_ALUout <= #3 0;
EX_MEM_B <= #3 0;
EX_MEM_IR <= #3 0;
EX_MEM_type <= #3 0;
BRANCH_Condition <= #3 0;
end

else
begin

// DATA-FORWARDING FOR DATA RAW DEPENDENCY WITH PREVIOUS INSTRUCTIONS

if ((MEM_WB_IR[31:26] == LW) && (ID_EX_IR[25:21] == MEM_WB_IR[20:16]))
ALUop1 = #3 MEM_WB_LMD;
else if((EX_MEM_type == RR_ALU) && (ID_EX_IR[25:21] == EX_MEM_IR[15:11]))
ALUop1 = #3 EX_MEM_ALUout;
else if((MEM_WB_type == RR_ALU) && (ID_EX_IR[25:21] == MEM_WB_IR[15:11]))
ALUop1 = #3 MEM_WB_ALUout;
else if ((EX_MEM_type == RM_ALU) &&(ID_EX_IR[25:21] == EX_MEM_IR[20:16]))
ALUop1 = #3 EX_MEM_ALUout;
else if ((MEM_WB_type == RM_ALU) && (ID_EX_IR[25:21] == MEM_WB_IR[20:16]))
ALUop1 = #3 MEM_WB_ALUout;
else
ALUop1 = #3 ID_EX_A;

if ((MEM_WB_IR[31:26] == LW) && ((ID_EX_type == RR_ALU) || (ID_EX_type == BRANCH)) && (ID_EX_IR[20:16] == MEM_WB_IR[20:16]))
ALUop2 = #3 MEM_WB_LMD; 
else if((EX_MEM_type == RR_ALU) && ((ID_EX_type == RR_ALU) || (ID_EX_type == BRANCH)) && (ID_EX_IR[20:16] == EX_MEM_IR[15:11]))
ALUop2 = #3 EX_MEM_ALUout;
else if((MEM_WB_type == RR_ALU) && ((ID_EX_type == RR_ALU) || (ID_EX_type == BRANCH)) && (ID_EX_IR[20:16] == MEM_WB_IR[15:11]))
ALUop2 = #3 MEM_WB_ALUout;
else if ((EX_MEM_type == RM_ALU) && ((ID_EX_type == RR_ALU) || (ID_EX_type == BRANCH)) && (ID_EX_IR[20:16] == EX_MEM_IR[20:16]))
ALUop2 = #3 EX_MEM_ALUout;
else if ((MEM_WB_type == RM_ALU) && ((ID_EX_type == RR_ALU) || (ID_EX_type == BRANCH)) && (ID_EX_IR[20:16] == MEM_WB_IR[20:16]))
ALUop2 = #3 MEM_WB_ALUout;   
else 
ALUop2 = #3 ID_EX_B;

case(ID_EX_type)

RR_ALU : begin               
               case(ID_EX_IR[31:26])
                ADD : EX_MEM_ALUout <= #3 ALUop1 + ALUop2;
                SUB : EX_MEM_ALUout <= #3 ALUop1 - ALUop2;
				MUL : EX_MEM_ALUout <= #3 ALUop1 * ALUop2;
				SLT : EX_MEM_ALUout <= #3 ALUop1 < ALUop2;
				AND : EX_MEM_ALUout <= #3 ALUop1 & ALUop2;
				OR  : EX_MEM_ALUout <= #3 ALUop1 | ALUop2;
				
				default : EX_MEM_ALUout <= #3 32'hxxxxxxxx;
			   endcase
				
		end
		
RM_ALU : begin
               case(ID_EX_IR[31:26])
			     ADDI : EX_MEM_ALUout <= #3 ALUop1 + ID_EX_Imm;
				 SUBI : EX_MEM_ALUout <= #3 ALUop1 - ID_EX_Imm;
				 SLTI : EX_MEM_ALUout <= #3 ALUop1 < ID_EX_Imm;
				 
				 default : EX_MEM_ALUout <= #3 32'hxxxxxxxx;
			   endcase
			   
         end
		 
LOAD,STORE : begin
                   EX_MEM_ALUout <= #3 ALUop1 + ID_EX_Imm;
                   EX_MEM_B <= #3 ALUop2;
             end
			 
BRANCH : begin
               EX_MEM_ALUout <= #3 ID_EX_NPC + ID_EX_Imm;
			   BRANCH_Condition <= #3 (ALUop1 == ALUop2);
		 end      			 
		 		 
endcase

EX_MEM_IR <= #3 ID_EX_IR;
EX_MEM_type <= #3 ID_EX_type;

end

end
end

// MEM STAGE
always@(posedge clkN)
begin

if(HALTED == 0)
begin

case (EX_MEM_type)
RR_ALU,RM_ALU : MEM_WB_ALUout <= #3 EX_MEM_ALUout;
LOAD : MEM_WB_LMD <= #3 Data_Mem[EX_MEM_ALUout];
STORE : Data_Mem[EX_MEM_ALUout] <= #3 EX_MEM_B;
endcase

MEM_WB_type <= #3 EX_MEM_type;
MEM_WB_IR <= #3 EX_MEM_IR;

end
end

// WB STAGE
always@(posedge clkP)
begin

if(HALTED == 0)
begin

case (MEM_WB_type)
RR_ALU : Reg_File[MEM_WB_IR[15:11]] <= #3 MEM_WB_ALUout;
RM_ALU : Reg_File[MEM_WB_IR[20:16]] <= #3 MEM_WB_ALUout;
LOAD : Reg_File[MEM_WB_IR[20:16]] <= #3 MEM_WB_LMD; 
HALT : HALTED <= #3 1'b1;
endcase

end
end


endmodule