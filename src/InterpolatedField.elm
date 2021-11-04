module InterpolatedField exposing (Content(..), InterpolatedField(..), InterpolationField(..), Variable(..), fieldParser, fromString, interpolate, interpolationField, referencedVariables, statementsHelp, toElmExpression, toElmString, toString, tokenParser, variableName)

import Dict exposing (Dict)
import Elm
import Elm.Pattern
import List.NonEmpty
import Parser exposing ((|.), (|=), Parser)
import String.Extra


type InterpolatedField
    = InterpolatedField String


variableName : Variable -> String
variableName (Variable name) =
    name


interpolate : Dict String String -> InterpolatedField -> String
interpolate interpolationValues (InterpolatedField raw) =
    case Parser.run fieldParser raw of
        Ok parsed ->
            parsed
                |> List.map
                    (\text ->
                        case text of
                            RawText rawText ->
                                rawText

                            InterpolatedText (Variable name) ->
                                interpolationValues
                                    |> Dict.get name
                                    |> Maybe.withDefault ""
                    )
                |> String.join ""

        Err error ->
            "TODO"


fromString : String -> InterpolatedField
fromString string =
    InterpolatedField string


toString : InterpolatedField -> String
toString (InterpolatedField raw) =
    raw


tokenParser : Parser Variable
tokenParser =
    Parser.succeed Variable
        |. Parser.token "$"
        |= Parser.oneOf
            [ Parser.succeed identity
                |. Parser.token "{"
                |= (Parser.chompWhile (\character -> character /= ' ' && character /= '\n' && character /= '}')
                        |> Parser.getChompedString
                   )
                |. Parser.token "}"
            , Parser.chompWhile (\character -> character /= ' ' && character /= '\n') |> Parser.getChompedString
            ]


fieldParser : Parser (List Content)
fieldParser =
    Parser.loop [] statementsHelp


statementsHelp : List Content -> Parser (Parser.Step (List Content) (List Content))
statementsHelp revStmts =
    Parser.oneOf
        [ Parser.end
            |> Parser.map (\_ -> Parser.Done (List.reverse revStmts))
        , tokenParser |> Parser.map (\raw -> Parser.Loop (InterpolatedText raw :: revStmts))
        , Parser.chompUntilEndOr "$" |> Parser.getChompedString |> Parser.map (\raw -> Parser.Loop (RawText raw :: revStmts))
        ]


type Content
    = RawText String
    | InterpolatedText Variable


type Variable
    = Variable String


interpolationField : String -> InterpolationField
interpolationField =
    InterpolationField


type InterpolationField
    = InterpolationField String


toElmString : InterpolatedField -> String
toElmString (InterpolatedField raw) =
    case Parser.run fieldParser raw of
        Ok contents ->
            contents
                |> List.map
                    (\value ->
                        case value of
                            RawText rawText ->
                                escapedAndQuoted rawText

                            InterpolatedText (Variable name) ->
                                name |> String.toLower |> String.Extra.camelize
                    )
                |> String.join " ++ "

        -- TODO only add parens if more than 1? Or leave that up to the calling code?
        Err error ->
            "TODO"


toElmExpression : InterpolatedField -> Elm.Expression
toElmExpression (InterpolatedField raw) =
    case Parser.run fieldParser raw of
        Ok contents ->
            contents
                |> List.map
                    (\value ->
                        case value of
                            RawText rawText ->
                                Elm.string rawText

                            InterpolatedText (Variable name) ->
                                name |> String.toLower |> String.Extra.camelize |> Elm.value
                    )
                |> List.NonEmpty.fromList
                |> Maybe.withDefault (List.NonEmpty.singleton (Elm.string ""))
                |> List.NonEmpty.foldr1 Elm.append

        Err error ->
            Elm.string "TODO"


referencedVariables : InterpolatedField -> List Variable
referencedVariables (InterpolatedField raw) =
    case raw |> Parser.run fieldParser of
        Ok parsed ->
            referencedVariables_ parsed

        Err _ ->
            -- TODO
            []


referencedVariables_ : List Content -> List Variable
referencedVariables_ contents =
    contents
        |> List.filterMap
            (\text ->
                case text of
                    RawText _ ->
                        Nothing

                    InterpolatedText variable ->
                        Just variable
            )


escapedAndQuoted : String -> String
escapedAndQuoted string =
    "\"" ++ (string |> String.replace "\"" "\\\"") ++ "\""
