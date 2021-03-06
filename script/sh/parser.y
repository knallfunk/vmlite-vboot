/* parser.y - The scripting parser.  */
/*
 *  GRUB  --  GRand Unified Bootloader
 *  Copyright (C) 2005,2006,2007,2008,2009  Free Software Foundation, Inc.
 *
 *  GRUB is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  GRUB is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with GRUB.  If not, see <http://www.gnu.org/licenses/>.
 */

%{
#if defined(_VHD_BOOT_) || defined(_VBOOT_EDIT_)
#include "script_sh.h"
#include "mm.h"
#include "misc.h"
#else
#include <grub/script_sh.h>
#include <grub/mm.h>
#include <grub/misc.h>
#endif

#define YYFREE		grub_free
#define YYMALLOC	grub_malloc
#define YYLTYPE_IS_TRIVIAL      0
#define YYENABLE_NLS	0

%}

%union {
  struct grub_script_cmd *cmd;
  struct grub_script_arglist *arglist;
  struct grub_script_arg *arg;
  char *string;
}

%token GRUB_PARSER_TOKEN_IF		"if"
%token GRUB_PARSER_TOKEN_WHILE		"while"
%token GRUB_PARSER_TOKEN_FUNCTION	"function"
%token GRUB_PARSER_TOKEN_MENUENTRY	"menuentry"
%token GRUB_PARSER_TOKEN_SNAPSHOTENTRY	"snapshotentry"
%token GRUB_PARSER_TOKEN_ELSE		"else"
%token GRUB_PARSER_TOKEN_THEN		"then"
%token GRUB_PARSER_TOKEN_FI		"fi"
%token GRUB_PARSER_TOKEN_ARG
%type <cmd> script_init script grubcmd command commands commandblock menuentry snapshotentry if
%type <arglist> arguments;
%type <arg> GRUB_PARSER_TOKEN_ARG;

%pure-parser
%lex-param { struct grub_parser_param *state };
%parse-param { struct grub_parser_param *state };

%%
/* It should be possible to do this in a clean way...  */
script_init:	{ state->err = 0; } script
		  {
		    state->parsed = $2;
		  }
;

script:		{ $$ = 0; }
                | '\n' { $$ = 0; }
                | commands { $$ = $1; }
		| function '\n' { $$ = 0; }
		| menuentry '\n' { $$ = $1; }		
		| error
		  {
		    $$ = 0;
		    yyerror (state, "Incorrect command");
		    state->err = 1;
		    yyerrok;
		  }
;

delimiter:	'\n'
		| ';'
		| delimiter '\n'
;

newlines:	/* Empty */
		| newlines '\n'
;



arguments:	GRUB_PARSER_TOKEN_ARG
		  {
		    $$ = grub_script_add_arglist (state, 0, $1);
		  }
		| arguments GRUB_PARSER_TOKEN_ARG
		  {
		    $$ = grub_script_add_arglist (state, $1, $2);
		  }
;

grubcmd:	arguments
		  {
		    $$ = grub_script_create_cmdline (state, $1);
		  }
;

/* A single command.  */
command:	grubcmd delimiter { $$ = $1; }
		| if delimiter 	{ $$ = $1; }
		| commandblock delimiter { $$ = $1; }	
		| snapshotentry delimiter { $$ = $1; }	
;

/* A block of commands.  */
commands:	command
		  {
		    $$ = grub_script_add_cmd (state, 0, $1);
		  }
		| command commands
		  {
		    struct grub_script_cmdblock *cmd;
		    cmd = (struct grub_script_cmdblock *) $2;
		    $$ = grub_script_add_cmd (state, cmd, $1);
		  }
;

/* A function.  Carefully save the memory that is allocated.  Don't
   change any stuff because it might seem like a fun thing to do!
   Special care was take to make sure the mid-rule actions are
   executed on the right moment.  So the `commands' rule should be
   recognized after executing the `grub_script_mem_record; and before
   `grub_script_mem_record_stop'.  */
function:	"function" GRUB_PARSER_TOKEN_ARG
		  {
		    grub_script_lexer_ref (state->lexerstate);
		  } newlines '{'
		  {
		    /* The first part of the function was recognized.
		       Now start recording the memory usage to store
		       this function.  */
		    state->func_mem = grub_script_mem_record (state);
		  } newlines commands '}'
		  {
		    struct grub_script *script;

		    /* All the memory usage for parsing this function
		       was recorded.  */
		    state->func_mem = grub_script_mem_record_stop (state,
								   state->func_mem);
		    script = grub_script_create ($8, state->func_mem);
		    if (script)
		      grub_script_function_create ($2, script);
		    grub_script_lexer_deref (state->lexerstate);
		  }
;

/* Carefully designed, together with `menuentry' so everything happens
   just in the expected order.  */
commandblock:	'{'
		  {
		    grub_script_lexer_ref (state->lexerstate);
		  }
                newlines commands '}'
                  {
		    grub_script_lexer_deref (state->lexerstate);
		    $$ = $4;
		  }
;

/* A menu entry.  Carefully save the memory that is allocated.  */
menuentry: "menuentry"
		  {		    
		    grub_script_lexer_ref (state->lexerstate);		    
		  } arguments newlines '{'
		  {
		    grub_script_lexer_record_start (state->lexerstate);
		    grub_enter_scope(state);		    
		  } newlines commands '}'
		  {
		    char *menu_entry;
		    menu_entry = grub_script_lexer_record_stop (state->lexerstate);		    
		    grub_script_lexer_deref (state->lexerstate);		    
		    $$ = grub_script_create_cmdmenu (state, $3, menu_entry, 0);
		    grub_leave_scope(state);
		  }		  
;

/* A snapshot entry.  Carefully save the memory that is allocated.  */
snapshotentry:	"snapshotentry" 
          {
            grub_script_lexer_ref (state->lexerstate);           
          }
          arguments newlines '{'
          {
            if (!state->lexerstate->record)
              grub_script_lexer_record_start (state->lexerstate);
            grub_enter_scope(state);        
			grub_current_scope(state)->startshot_pos = state->lexerstate->recordpos;
          }	  
          newlines commands '}'
          {
            struct grub_script_cmd *entry;
            scope_t *scope = grub_current_scope(state);
            scope_t *parent_scope;
                       
            int len = state->lexerstate->recordpos - scope->startshot_pos;
            char *snapshot_txt = grub_malloc(len);
            
            if (snapshot_txt)
            {
				grub_strncpy(snapshot_txt, state->lexerstate->recording + scope->startshot_pos, len);
				snapshot_txt[len - 1] = '\0';
				//grub_printf("'%s'\n", snapshot_txt);
				if (state->lexerstate->recordpos > 0)
				{
				  if (state->lexerstate->recording[state->lexerstate->recordpos - 1] != '}')
				  {
					  grub_printf ("Internal error while parsing snapshot entry: '%c'", state->lexerstate->recording[state->lexerstate->recordpos - 1]);
#if defined(_VHD_BOOT_) || defined(WIN32)	/* can't allow infite loop inside kernel */					 
					  for (;;); /* XXX */				  
#endif						  
				  }				 
				}						
				grub_script_lexer_deref (state->lexerstate);				
				//$$ = $7;
		    }
		    
		    entry = grub_script_create_cmdmenu (state, $3, snapshot_txt, 1);
		    
		    parent_scope = grub_parent_scope(state);
		    if (parent_scope)
		    {		        
				if (parent_scope->snapshots == NULL)
				{
					parent_scope->snapshots = (struct grub_script_cmd_menuentry *)entry;
				}
				else
				{
					// we need to append to the last
					struct grub_script_cmd_menuentry *last_snapshot = parent_scope->snapshots;
					while (last_snapshot->next)
					{
						last_snapshot = last_snapshot->next;
					}
					
					last_snapshot->next = (struct grub_script_cmd_menuentry *)entry;
				}
		    }
		    grub_leave_scope(state);
		    $$ = entry;
		  }
;

/* The first part of the if statement.  It's used to switch the lexer
   to a state in which it demands more tokens.  */
if_statement:	"if" { grub_script_lexer_ref (state->lexerstate); }
;

/* The if statement.  */
if:		 if_statement commands "then" newlines commands "fi"
		  {
		    $$ = grub_script_create_cmdif (state, $2, $5, 0);
		    grub_script_lexer_deref (state->lexerstate);
		  }
		 | if_statement commands "then" newlines commands "else" newlines commands  "fi"
		  {
		    $$ = grub_script_create_cmdif (state, $2, $5, $8);
		    grub_script_lexer_deref (state->lexerstate);
		  }
;

		  