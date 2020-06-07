module Color exposing (Format, Color, parseANSI, parseANSIwithError, defaultFormat)
import Html
import Html.Attributes as Attributes

import Parser exposing (..)
import Set
import Debug

{- 
  token from a stream of data with ANSI escape values
  See: https://en.wikipedia.org/wiki/ANSI_escape_code
  (Note, only the SGR command is supported)
-}
type AnsiToken
  = Content String  -- a normal bit of text to be formatted
  | SGR (List Int)  -- 'set graphics rendition'

--the CSI command, ESC + [
csi = '\u{001b}'

content : Parser AnsiToken
content =
  succeed Content
  |= variable
    { start = (/=) csi
    , inner = (/=) csi
    , reserved = Set.empty
    }

-- may need to remake this to support better error messages
sgr : Parser AnsiToken
sgr =
  succeed SGR
  |= sequence
    { start = "\u{001b}["
    , separator = ";"
    , end = "m"
    , spaces = succeed ()
    , item = int
    , trailing = Forbidden
    }

ansiToken : Parser (List AnsiToken)
ansiToken =
  sequence
  { start = ""
  , separator = ""
  , end = ""
  , item = oneOf [ sgr, content ]
  , spaces = succeed ()
  , trailing = Optional
  }

run = Parser.run
test = "\u{001b}[31mmeme\u{001b}[0m"


type alias Format =
  { foreground : Color
  , background : Color
  , bold : Bool
  , italic : Bool
  , underline : Bool
  , strike : Bool
  , blink : Bool
  , reverse : Bool
  }

defaultFormat : Format
defaultFormat = 
  { foreground = Default
  , background = Default
  , bold = False
  , italic = False
  , underline = False
  , strike = False
  , blink = False
  , reverse = False
  }

type Color
  = Black
  | Red
  | Green
  | Yellow
  | Blue
  | Magenta
  | Cyan
  | White
  | Default
  | BrightBlack
  | BrightRed
  | BrightGreen
  | BrightYellow
  | BrightBlue
  | BrightMagenta
  | BrightCyan
  | BrightWhite

type ColorType
  = Background
  | Foreground

colorName : Color -> Maybe String
colorName color =
  case color of
    -- the basic colors
    Black   -> Just "black"
    Red     -> Just "red"
    Green   -> Just "green"
    Yellow  -> Just "yellow"
    Blue    -> Just "blue"
    Magenta -> Just "magenta"
    Cyan    -> Just "cyan"
    White   -> Just "white"
    -- the nonstandard bright colors, often not supported
    BrightBlack   -> Just "bright-black"
    BrightRed     -> Just "bright-red"
    BrightGreen   -> Just "bright-green"
    BrightYellow  -> Just "bright-yellow"
    BrightBlue    -> Just "bright-blue"
    BrightMagenta -> Just "bright-magenta"
    BrightCyan    -> Just "bright-cyan"
    BrightWhite   -> Just "bright-white"
    _ -> Nothing

colorAttr : Color -> ColorType -> Maybe (Html.Attribute msg)
colorAttr color cType =
  -- is there a simple string representation?
  -- TODO: handle backgrounds
  case (colorName color) of
    Just str -> 
      case cType of
        Foreground -> Just <| Attributes.class ("term-" ++ str)
        Background -> Just <| Attributes.class ("term-" ++ str ++ "-bg")
    Nothing -> Nothing

format : Format -> String -> Html.Html msg
format fmt cntnt =
  let
    (foreground, background) = 
      if fmt.reverse then 
        ( colorAttr fmt.background Foreground, 
          colorAttr fmt.foreground Background)
      else
        ( colorAttr fmt.foreground Foreground, 
          colorAttr fmt.background Background)
    attributes = []
      |> (::) foreground
      |> (::) background
      |> (++) (decorationAttr fmt)
      |> List.filterMap identity
  in
  Html.span attributes [Html.text cntnt]

{- 
  Extract the CSS classes based on the decoration attributes.
  All of this confusion occurs because both underline and strikethrough
  rely on the 'text-decoration' CSS property. If a bit of text
  is both underlined and crossed out, then applying the .term-underline
  and .term-strike classes would cause them to be overwritten.
-}
decorationAttr : Format -> List (Maybe (Html.Attribute msg))
decorationAttr fmt =
  if fmt.strike && fmt.underline
  then
    [ Just (Attributes.class "term-underline-strike") ]
    |> (::) ( maybeIf fmt.bold (Attributes.class "term-bold") )
    |> (::) ( maybeIf fmt.italic (Attributes.class "term-italic") )
    |> (::) ( maybeIf fmt.blink (Attributes.class "term-blink") )
    |> (::) ( maybeIf fmt.reverse (Attributes.class "term-reverse") )
  else
    []
    |> (::) ( maybeIf fmt.bold (Attributes.class "term-bold") )
    |> (::) ( maybeIf fmt.italic (Attributes.class "term-italic") )
    |> (::) ( maybeIf fmt.underline (Attributes.class "term-underline") )
    |> (::) ( maybeIf fmt.blink (Attributes.class "term-blink") )
    |> (::) ( maybeIf fmt.reverse (Attributes.class "term-reverse") )
    |> (::) ( maybeIf fmt.strike (Attributes.class "term-strike") )

maybeIf : Bool -> item -> Maybe item
maybeIf condition item = if condition then Just item else Nothing

handleSGR : Int -> Format -> Format
handleSGR code fmt =
  case code of
    -- clear decoration
    0 -> defaultFormat
    -- text decoration on
    1 -> { fmt | bold = True }
    3 -> { fmt | italic = True }
    4 -> { fmt | underline = True }
    {- 
      for the sake of simplicity, we don't distinguish
      between slow vs. fast blink
    -}
    5 -> { fmt | blink = True }
    6 -> { fmt | blink = True }
    7 -> { fmt | reverse = True }
    9 -> { fmt | strike = True }
    -- text decoration off
    21 -> { fmt | bold = False }
    23 -> { fmt | italic = False }
    24 -> { fmt | underline = False }
    27 -> { fmt | reverse = False }
    29 -> { fmt | strike = False }
    -- foreground coloring
    30 -> { fmt | foreground = Black }
    31 -> { fmt | foreground = Red }
    32 -> { fmt | foreground = Green }
    33 -> { fmt | foreground = Yellow }
    34 -> { fmt | foreground = Blue }
    35 -> { fmt | foreground = Magenta }
    36 -> { fmt | foreground = Cyan }
    37 -> { fmt | foreground = White }
    38 -> fmt -- placeholder
    39 -> { fmt | foreground = Default }
    -- background colors
    40 -> { fmt | background = Black }
    41 -> { fmt | background = Red }
    42 -> { fmt | background = Green }
    43 -> { fmt | background = Yellow }
    44 -> { fmt | background = Blue }
    45 -> { fmt | background = Magenta }
    46 -> { fmt | background = Cyan }
    47 -> { fmt | background = White }
    48 -> fmt -- placeholder
    49 -> { fmt | background = Default }
    -- bright foreground colors (nonstandard)
    90 ->  { fmt | foreground = BrightBlack }
    91 ->  { fmt | foreground = BrightRed }
    92 ->  { fmt | foreground = BrightGreen }
    93 ->  { fmt | foreground = BrightYellow }
    94 ->  { fmt | foreground = BrightBlue }
    95 ->  { fmt | foreground = BrightMagenta }
    96 ->  { fmt | foreground = BrightCyan }
    97 ->  { fmt | foreground = BrightWhite }
    -- bright background colors (nonstandard)
    100 -> { fmt | background = BrightBlack }
    101 -> { fmt | background = BrightRed }
    102 -> { fmt | background = BrightGreen }
    103 -> { fmt | background = BrightYellow }
    104 -> { fmt | background = BrightBlue }
    105 -> { fmt | background = BrightMagenta }
    106 -> { fmt | background = BrightCyan }
    107 -> { fmt | background = BrightWhite }
    _ -> fmt
  
type alias Buffer msg =
  { completed : List (Html.Html msg)
  , format : Maybe Format
  }

handleToken : AnsiToken -> Buffer msg -> Buffer msg
handleToken token buf =
  case token of
    SGR codes ->
      case buf.format of
        Just fmt ->
          { buf | format = Just <| Debug.log "sgr: " (List.foldl handleSGR fmt codes) }
        -- if we aren't doing the format thing, then just ignore the SGR
        Nothing -> buf
    Content cntent ->
        let fmt = Maybe.withDefault defaultFormat buf.format in
        { buf | completed = (format fmt cntent) :: buf.completed }


handleTokens : Maybe Format -> List AnsiToken -> (Maybe Format, List (Html.Html msg))
handleTokens current tokens =
  let 
    buf = Buffer [] current 
    updated = List.foldl handleToken buf tokens
  in
  (updated.format, List.reverse updated.completed)

parseANSI : Maybe Format -> String -> Result (List Parser.DeadEnd) (Maybe Format, List (Html.Html msg))
parseANSI fmt data =
  Result.map (handleTokens fmt) (Parser.run ansiToken data)

-- parse an ANSI stream and convert any underlying error messages into Html nodes
parseANSIwithError : Maybe Format -> String -> (Maybe Format, List (Html.Html msg))
parseANSIwithError fmt data =
  case (parseANSI fmt data) of
    Err (deadEnd) -> (fmt , [ Html.text (Parser.deadEndsToString deadEnd) ])
    Ok value -> value