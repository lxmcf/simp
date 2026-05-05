package main

Theme :: struct {
    text:        string,
    comment:     string,
    string_lit:  string,
    number:      string,
    keyword:     string,
    declaration: string,
    statement:   string,
    type_name:   string,
    constant:    string,
    function:    string,
    operator:    string,
    error:       string,
}

// Truecolor Solarized-inspired theme (Subdued, highly readable on light and dark)
THEME_SOLARIZED :: Theme {
    text        = "",
    comment     = "\033[3;38;2;147;161;161m", // Base1 (subtle gray, italic)
    string_lit  = "\033[38;2;42;161;152m", // Cyan
    number      = "\033[38;2;42;161;152m", // Cyan
    keyword     = "\033[38;2;133;153;0m", // Green
    declaration = "\033[38;2;38;139;210m", // Blue
    statement   = "\033[38;2;133;153;0m", // Green
    type_name   = "\033[38;2;181;137;0m", // Yellow
    constant    = "\033[38;2;211;54;130m", // Magenta
    function    = "\033[38;2;38;139;210m", // Blue
    operator    = "",
    error       = "\033[38;2;220;50;47m", // Red
}

// Dracula (Vibrant, high contrast, purples and pinks)
THEME_DRACULA :: Theme {
    text        = "",
    comment     = "\033[3;38;2;98;114;164m", // Grey/Blue (Italic)
    string_lit  = "\033[38;2;241;250;140m", // Yellow
    number      = "\033[38;2;189;147;249m", // Purple
    keyword     = "\033[38;2;255;121;198m", // Pink
    declaration = "\033[38;2;139;233;253m", // Cyan
    statement   = "\033[38;2;255;121;198m", // Pink
    type_name   = "\033[38;2;139;233;253m", // Cyan
    constant    = "\033[38;2;189;147;249m", // Purple
    function    = "\033[38;2;80;250;123m", // Green
    operator    = "\033[38;2;255;121;198m", // Pink
    error       = "\033[38;2;255;85;85m", // Red
}

// Monokai (Classic Sublime Text, warm and punchy)
THEME_MONOKAI :: Theme {
    text        = "",
    comment     = "\033[3;38;2;117;113;94m", // Brown/Grey (Italic)
    string_lit  = "\033[38;2;230;219;116m", // Yellow
    number      = "\033[38;2;174;129;255m", // Purple
    keyword     = "\033[38;2;249;38;114m", // Pink/Red
    declaration = "\033[38;2;102;217;239m", // Cyan
    statement   = "\033[38;2;249;38;114m", // Pink/Red
    type_name   = "\033[38;2;102;217;239m", // Cyan
    constant    = "\033[38;2;174;129;255m", // Purple
    function    = "\033[38;2;166;226;46m", // Green
    operator    = "\033[38;2;249;38;114m", // Pink/Red
    error       = "\033[38;2;253;151;31m", // Orange
}

// Nord (Cool, icy, clean aesthetics)
THEME_NORD :: Theme {
    text        = "",
    comment     = "\033[3;38;2;76;86;106m", // Slate (Italic)
    string_lit  = "\033[38;2;163;190;140m", // Pale Green
    number      = "\033[38;2;180;142;173m", // Pale Purple
    keyword     = "\033[38;2;129;161;193m", // Soft Blue
    declaration = "\033[38;2;143;188;187m", // Frost Cyan
    statement   = "\033[38;2;129;161;193m", // Soft Blue
    type_name   = "\033[38;2;143;188;187m", // Frost Cyan
    constant    = "\033[38;2;208;135;112m", // Orange
    function    = "\033[38;2;136;192;208m", // Frost Blue
    operator    = "\033[38;2;129;161;193m", // Soft Blue
    error       = "\033[38;2;191;97;106m", // Red
}

// VS Code Modern Dark Theme
THEME_VISUAL_STUDIO :: Theme {
    text        = "\033[38;2;212;212;212m", // Light Gray
    comment     = "\033[3;38;2;106;153;85m", // Green (Italic)
    string_lit  = "\033[38;2;206;145;120m", // Pale Orange
    number      = "\033[38;2;181;206;168m", // Pale Green
    keyword     = "\033[38;2;197;134;192m", // Purple
    declaration = "\033[38;2;86;156;214m", // Blue
    statement   = "\033[38;2;197;134;192m", // Purple
    type_name   = "\033[38;2;78;201;176m", // Teal
    constant    = "\033[38;2;79;193;255m", // Light Blue
    function    = "\033[38;2;220;220;170m", // Pale Yellow
    operator    = "\033[38;2;212;212;212m", // Light Gray
    error       = "\033[38;2;244;71;71m", // Red
}
