#+private

package simp

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

Token_Type :: distinct enum {
    EOF,
    Ident,
    Number,
    String,
    Plus,
    Minus,
    Star,
    Slash,
    Equals,
    DoubleEquals,
    NotEqual,
    Less,
    Greater,
    LessEqual,
    GreaterEqual,
    LParen,
    RParen,
    LBrace,
    RBrace,
    Comma,
    Colon,
    DoubleColon,
    Newline,
    And,
    Or,
    Not,
    LBracket,
    RBracket,
    Dot,
    Percent,
    PlusEquals,
    MinusEquals,
    StarEquals,
    SlashEquals,
    PercentEquals,
    Ellipsis,
    Semicolon,
}

Token_Keyword :: distinct enum {
    None,

    // BUILTIN DIRECTIVES
    Import,
    Put,
    Pull,
    Sleep,
    Delete,
    Label,
    Goto,
    New,
    Exit,

    // KEYWORDS
    And,
    Or,
    Not,
    While,
    For,
    Foreach,
    In,
    Break,
    Continue,
    Function,
    Else,
    If,
    Let,
    Const,
    Then,
    To,
    Step,
    Return,
    True,
    False,
    Null,
    Object,
    Array,
    Ellipsis,

    // TYPES
    Int,
    Float,
    String,
    Bool,
    Type,
}

Token :: distinct struct {
    type:    Token_Type,
    keyword: Token_Keyword,
    text:    string,
    line:    int,
}

_tokenise_and_resolve :: proc(state: ^State, script: string, filename: string, visited_files: ^map[string]bool) -> ([]Token, bool) {
    script_to_use := script

    if state != nil {
        script_to_use = strings.clone(script)
        append(&state.imported_scripts, script_to_use)
    }

    raw_tokens, ok := _tokenise(state, script_to_use)
    if !ok {
        if state != nil {
            state.should_close = true
        }

        return nil, false
    }

    resolved_tokens := make([dynamic]Token, context.temp_allocator)
    if filename != "" {
        visited_files^[filename] = true
    }

    token_index := 0
    for token_index < len(raw_tokens) {
        token := raw_tokens[token_index]

        if token.keyword == .Import {
            has_next_token := token_index + 1 < len(raw_tokens)

            if has_next_token && raw_tokens[token_index + 1].type == .String {
                imported_path := raw_tokens[token_index + 1].text
                token_index += 2

                absolute_import_path := imported_path
                if filename != "" {
                    source_directory := filepath.dir(filename)
                    absolute_import_path, _ = filepath.join({source_directory, imported_path}, context.temp_allocator)
                    absolute_import_path, _ = filepath.clean(absolute_import_path, context.temp_allocator)
                }

                if absolute_import_path not_in visited_files^ {
                    file_data, read_error := os.read_entire_file(absolute_import_path, context.temp_allocator)
                    if read_error == nil {
                        sub_tokens, sub_tokens_ok := _tokenise_and_resolve(state, string(file_data), absolute_import_path, visited_files)

                        if !sub_tokens_ok {
                            return nil, false
                        }

                        for sub_token in sub_tokens {
                            append(&resolved_tokens, sub_token)
                        }
                    } else {
                        error_message := fmt.aprintf("Could not import file '%s' (Resolved as: %s)", imported_path, absolute_import_path)

                        if state != nil {
                            state.log_proc(.Warning, error_message, token.line)
                            state.should_close = true
                        } else {
                            default_log_proc(.Warning, error_message, token.line)
                        }

                        delete(error_message)

                        return nil, false
                    }
                }

                continue
            } else {
                error_message := fmt.aprintf("Expected string literal after 'import'")

                if state != nil {
                    state.log_proc(.Error, error_message, token.line)
                    state.should_close = true
                } else {
                    default_log_proc(.Error, error_message, token.line)
                }

                delete(error_message)

                return nil, false
            }
        }

        append(&resolved_tokens, token)
        token_index += 1
    }

    return resolved_tokens[:], true
}

@(private = "file")
_tokenise :: proc(state: ^State, script: string) -> ([]Token, bool) {
    tokens := make([dynamic]Token, context.temp_allocator)
    char_index := 0
    line_number := 1

    for char_index < len(script) {
        character := script[char_index]

        switch character {
        case ' ', '\t':
            char_index += 1

        case '\r':
            if char_index + 1 < len(script) && script[char_index + 1] == '\n' {
                append(&tokens, Token{type = .Newline, keyword = .None, text = "\n", line = line_number})
                char_index += 2
            } else {
                append(&tokens, Token{type = .Newline, keyword = .None, text = "\n", line = line_number})
                char_index += 1
            }
            line_number += 1

        case '\n':
            append(&tokens, Token{type = .Newline, keyword = .None, text = "\n", line = line_number})
            char_index += 1
            line_number += 1

        case ';':
            append(&tokens, Token{type = .Semicolon, keyword = .None, text = ";", line = line_number})
            char_index += 1

        case '+':
            if char_index + 1 < len(script) && script[char_index + 1] == '=' {
                append(&tokens, Token{type = .PlusEquals, keyword = .None, text = "+=", line = line_number})
                char_index += 2
            } else {
                append(&tokens, Token{type = .Plus, keyword = .None, text = "+", line = line_number})
                char_index += 1
            }

        case '-':
            if char_index + 2 < len(script) && script[char_index + 1] == '-' && script[char_index + 2] == '-' {
                char_index += 3
                for char_index < len(script) {
                    if script[char_index] == '\n' {
                        line_number += 1
                    } else if script[char_index] == '\r' {
                        if char_index + 1 < len(script) && script[char_index + 1] == '\n' {
                        } else {
                            line_number += 1
                        }
                    }

                    if char_index + 2 < len(script) && script[char_index] == '-' && script[char_index + 1] == '-' && script[char_index + 2] == '-' {
                        char_index += 3
                        break
                    }
                    char_index += 1
                }
            } else if char_index + 1 < len(script) && script[char_index + 1] == '=' {
                append(&tokens, Token{type = .MinusEquals, keyword = .None, text = "-=", line = line_number})
                char_index += 2
            } else {
                append(&tokens, Token{type = .Minus, keyword = .None, text = "-", line = line_number})
                char_index += 1
            }

        case '*':
            if char_index + 1 < len(script) && script[char_index + 1] == '=' {
                append(&tokens, Token{type = .StarEquals, keyword = .None, text = "*=", line = line_number})
                char_index += 2
            } else {
                append(&tokens, Token{type = .Star, keyword = .None, text = "*", line = line_number})
                char_index += 1
            }

        case '/':
            if char_index + 1 < len(script) && script[char_index + 1] == '/' {
                for char_index < len(script) && script[char_index] != '\n' && script[char_index] != '\r' {
                    char_index += 1
                }
            } else if char_index + 1 < len(script) && script[char_index + 1] == '=' {
                append(&tokens, Token{type = .SlashEquals, keyword = .None, text = "/=", line = line_number})
                char_index += 2
            } else {
                append(&tokens, Token{type = .Slash, keyword = .None, text = "/", line = line_number})
                char_index += 1
            }

        case '%':
            if char_index + 1 < len(script) && script[char_index + 1] == '=' {
                append(&tokens, Token{type = .PercentEquals, keyword = .None, text = "%=", line = line_number})
                char_index += 2
            } else {
                append(&tokens, Token{type = .Percent, keyword = .None, text = "%", line = line_number})
                char_index += 1
            }

        case '[':
            append(&tokens, Token{type = .LBracket, keyword = .None, text = "[", line = line_number})
            char_index += 1

        case ']':
            append(&tokens, Token{type = .RBracket, keyword = .None, text = "]", line = line_number})
            char_index += 1

        case '{':
            append(&tokens, Token{type = .LBrace, keyword = .None, text = "{", line = line_number})
            char_index += 1

        case '}':
            append(&tokens, Token{type = .RBrace, keyword = .None, text = "}", line = line_number})
            char_index += 1

        case '.':
            if char_index + 2 < len(script) && script[char_index + 1] == '.' && script[char_index + 2] == '.' {
                append(&tokens, Token{type = .Ellipsis, keyword = .Ellipsis, text = "...", line = line_number})
                char_index += 3
            } else if char_index + 1 < len(script) && _is_digit(script[char_index + 1]) {
                start_index := char_index
                dot_count := 1
                char_index += 1

                for char_index < len(script) && (_is_digit(script[char_index]) || script[char_index] == '.') {
                    if script[char_index] == '.' {
                        dot_count += 1
                    }
                    char_index += 1
                }

                if dot_count > 1 {
                    error_message := fmt.aprintf("Invalid numeric literal '%s', too many decimal points", script[start_index:char_index])
                    state.log_proc(.Error, error_message, line_number)
                    delete(error_message)

                    return nil, false
                }

                append(&tokens, Token{type = .Number, keyword = .None, text = script[start_index:char_index], line = line_number})
            } else {
                append(&tokens, Token{type = .Dot, keyword = .None, text = ".", line = line_number})
                char_index += 1
            }

        case '=':
            if char_index + 1 < len(script) && script[char_index + 1] == '=' {
                append(&tokens, Token{type = .DoubleEquals, keyword = .None, text = "==", line = line_number})
                char_index += 2
            } else {
                append(&tokens, Token{type = .Equals, keyword = .None, text = "=", line = line_number})
                char_index += 1
            }

        case '<':
            if char_index + 1 < len(script) && script[char_index + 1] == '=' {
                append(&tokens, Token{type = .LessEqual, keyword = .None, text = "<=", line = line_number})
                char_index += 2
            } else if char_index + 1 < len(script) && script[char_index + 1] == '>' {
                append(&tokens, Token{type = .NotEqual, keyword = .None, text = "<>", line = line_number})
                char_index += 2
            } else {
                append(&tokens, Token{type = .Less, keyword = .None, text = "<", line = line_number})
                char_index += 1
            }

        case '>':
            if char_index + 1 < len(script) && script[char_index + 1] == '=' {
                append(&tokens, Token{type = .GreaterEqual, keyword = .None, text = ">=", line = line_number})
                char_index += 2
            } else {
                append(&tokens, Token{type = .Greater, keyword = .None, text = ">", line = line_number})
                char_index += 1
            }

        case '(':
            append(&tokens, Token{type = .LParen, keyword = .None, text = "(", line = line_number})
            char_index += 1

        case ')':
            append(&tokens, Token{type = .RParen, keyword = .None, text = ")", line = line_number})
            char_index += 1

        case ',':
            append(&tokens, Token{type = .Comma, keyword = .None, text = ",", line = line_number})
            char_index += 1

        case ':':
            if char_index + 1 < len(script) && script[char_index + 1] == ':' {
                append(&tokens, Token{type = .DoubleColon, keyword = .None, text = "::", line = line_number})
                char_index += 2
            } else {
                append(&tokens, Token{type = .Colon, keyword = .None, text = ":", line = line_number})
                char_index += 1
            }

        case '!':
            if char_index + 1 < len(script) && script[char_index + 1] == '=' {
                append(&tokens, Token{type = .NotEqual, keyword = .None, text = "!=", line = line_number})
                char_index += 2
            } else {
                append(&tokens, Token{type = .Not, keyword = .Not, text = "!", line = line_number})
                char_index += 1
            }

        case '&':
            if char_index + 1 < len(script) && script[char_index + 1] == '&' {
                append(&tokens, Token{type = .And, keyword = .And, text = "&&", line = line_number})
                char_index += 2
            } else {
                char_index += 1
            }

        case '|':
            if char_index + 1 < len(script) && script[char_index + 1] == '|' {
                append(&tokens, Token{type = .Or, keyword = .Or, text = "||", line = line_number})
                char_index += 2
            } else {
                char_index += 1
            }

        case '"':
            char_index += 1
            start_line_number := line_number
            string_builder := strings.builder_make(context.temp_allocator)
            is_string_closed := false

            for char_index < len(script) {
                if script[char_index] == '"' {
                    is_string_closed = true
                    break
                }

                if script[char_index] == '\\' && char_index + 1 < len(script) {
                    char_index += 1
                    switch script[char_index] {
                    case 'n':
                        strings.write_byte(&string_builder, '\n')
                    case 't':
                        strings.write_byte(&string_builder, '\t')
                    case 'r':
                        strings.write_byte(&string_builder, '\r')
                    case '\\':
                        strings.write_byte(&string_builder, '\\')
                    case '"':
                        strings.write_byte(&string_builder, '"')
                    case '\n':
                        line_number += 1
                    case '\r':
                        if char_index + 1 < len(script) && script[char_index + 1] == '\n' {
                            char_index += 1
                        }
                        line_number += 1
                    case:
                        strings.write_byte(&string_builder, '\\')
                        strings.write_byte(&string_builder, script[char_index])
                    }
                } else {
                    if script[char_index] == '\n' {
                        line_number += 1
                    } else if script[char_index] == '\r' {
                        if char_index + 1 < len(script) && script[char_index + 1] == '\n' {
                        } else {
                            line_number += 1
                        }
                    }

                    strings.write_byte(&string_builder, script[char_index])
                }

                char_index += 1
            }

            if !is_string_closed {
                error_message := fmt.aprintf("Unterminated string literal")
                state.log_proc(.Error, error_message, start_line_number)
                delete(error_message)

                return nil, false
            }

            string_value := strings.to_string(string_builder)
            if state != nil {
                string_value = strings.clone(string_value, state.allocator)
            }

            append(&tokens, Token{type = .String, keyword = .None, text = string_value, line = start_line_number})

            if char_index < len(script) {
                char_index += 1
            }

        case:
            if _is_digit(character) {
                start_index := char_index
                dot_count := 0

                for char_index < len(script) && (_is_digit(script[char_index]) || script[char_index] == '.') {
                    if script[char_index] == '.' {
                        dot_count += 1
                    }
                    char_index += 1
                }

                if dot_count > 1 {
                    error_message := fmt.aprintf("Invalid numeric literal '%s', too many decimal points", script[start_index:char_index])
                    state.log_proc(.Error, error_message, line_number)
                    delete(error_message)
                    return nil, false
                }

                append(&tokens, Token{type = .Number, keyword = .None, text = script[start_index:char_index], line = line_number})
            } else if _is_character(character) || character == '_' || character == '$' {
                start_index := char_index

                for char_index < len(script) && (_is_character(script[char_index]) || _is_digit(script[char_index]) || script[char_index] == '_' || script[char_index] == '$') {
                    char_index += 1
                }

                identifier_text := script[start_index:char_index]

                keyword := Token_Keyword.None
                switch identifier_text {
                case "import":
                    keyword = .Import
                case "put":
                    keyword = .Put
                case "pull":
                    keyword = .Pull
                case "sleep":
                    keyword = .Sleep
                case "delete":
                    keyword = .Delete
                case "label":
                    keyword = .Label
                case "goto":
                    keyword = .Goto
                case "new":
                    keyword = .New
                case "exit":
                    keyword = .Exit
                case "and":
                    keyword = .And
                case "or":
                    keyword = .Or
                case "not":
                    keyword = .Not
                case "while":
                    keyword = .While
                case "for":
                    keyword = .For
                case "foreach":
                    keyword = .Foreach
                case "in":
                    keyword = .In
                case "break":
                    keyword = .Break
                case "continue":
                    keyword = .Continue
                case "function":
                    keyword = .Function
                case "else":
                    keyword = .Else
                case "if":
                    keyword = .If
                case "let":
                    keyword = .Let
                case "const":
                    keyword = .Const
                case "then":
                    keyword = .Then
                case "to":
                    keyword = .To
                case "step":
                    keyword = .Step
                case "return":
                    keyword = .Return
                case "true":
                    keyword = .True
                case "false":
                    keyword = .False
                case "null":
                    keyword = .Null
                case "object":
                    keyword = .Object
                case "array":
                    keyword = .Array
                case "int":
                    keyword = .Int
                case "float":
                    keyword = .Float
                case "string":
                    keyword = .String
                case "bool":
                    keyword = .Bool
                case "type":
                    keyword = .Type
                }

                #partial switch keyword {
                case .And:
                    append(&tokens, Token{type = .And, keyword = .And, text = "and", line = line_number})

                case .Or:
                    append(&tokens, Token{type = .Or, keyword = .Or, text = "or", line = line_number})

                case .Not:
                    append(&tokens, Token{type = .Not, keyword = .Not, text = "not", line = line_number})

                case:
                    append(&tokens, Token{type = .Ident, keyword = keyword, text = identifier_text, line = line_number})
                }
            } else {
                error_message := fmt.aprintf("Unrecognized character '%c'", character)
                state.log_proc(.Error, error_message, line_number)
                delete(error_message)

                return nil, false
            }
        }
    }

    return tokens[:], true
}
