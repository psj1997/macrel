module Main exposing (..)

import Bootstrap.Alert as Alert
import Bootstrap.Button as Button
import Bootstrap.CDN as CDN
import Bootstrap.Form as Form
import Bootstrap.Form.Textarea as Textarea
import Bootstrap.Grid as Grid
import Bootstrap.Grid.Col as Col
import Bootstrap.Grid.Row as Row
import Bootstrap.Popover as Popover
import Bootstrap.Text as Text
import Bootstrap.Table as Table
import Bootstrap.Spinner as Spinner

import Html exposing (..)
import Html.Attributes exposing (class, for, href, placeholder)
import Html.Events exposing (..)

import Http

import File.Download as Download

import Json.Decode as D
import Browser

type OperationType = Contigs | Peptides

type alias SequenceResult =
    { amp_family : String
    , amp_probability : Float
    , access : String
    , hemolytic : String
    , hemolyticP : Float
    , sequence : String }

type alias QueryModel =
    { optype : Maybe OperationType
    , facontent : String
    , helpPopoverState : Popover.State
    }

type Model =
        Query QueryModel
        | Loading
        | Results APIResult


type Msg
    = NoMsg
    | SelectOp OperationType
    | UpdateFacontent String
    | HelpPopover Popover.State
    | SetExample
    | SubmitData
    | ResultsData (Result Http.Error APIResult)
    | DownloadResults


type APIResult =
        APIResultOK { message : String
        , macrelVersion : String
        , rawdata : String
        , data : List SequenceResult
        }
        | APIError String

decodeSequenceResult : D.Decoder SequenceResult
decodeSequenceResult = D.map6 SequenceResult
    (D.field "AMP_family" D.string)
    (D.field "AMP_probability" D.float)
    (D.field "Access" D.string)
    (D.field "Hemolytic" D.string)
    (D.field "Hemolytic_probability" D.float)
    (D.field "Sequence" D.string)

decodeAPIResult : D.Decoder APIResult
decodeAPIResult =
    let
        bAPIResultOK m v r d = APIResultOK { message = m, macrelVersion = v, rawdata = r, data = d }
    in D.field "code" D.int
        |> D.andThen (\c ->
            if c == 0
                then D.map  APIError (D.field "message" D.string)
                else D.map4 bAPIResultOK
                        (D.field "message" D.string)
                        (D.field "macrel_version" D.string)
                        (D.field "rawdata" D.string)
                        (D.field "data" (D.field "objects" (D.list decodeSequenceResult))))

main : Program () Model Msg
main =
    Browser.document
        { init = init
        , view = view
        , update = update
        , subscriptions = \_ -> Sub.none
        }

init : () -> ( Model, Cmd Msg )
init () =
    ( Query { optype = Nothing
      , facontent = ""
      , helpPopoverState = Popover.initialState
      }
    , Cmd.none
    )

-- UPDATE

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        ifQuery f = case model of
            Query qm ->
                let
                    (qmpost, c) = f qm
                in (Query qmpost, c)
            _ -> (model, Cmd.none)
    in case msg of
        NoMsg ->
            ( model, Cmd.none )

        SelectOp p -> ifQuery <| \qmodel ->
                -- Iff the example input is selected, switch it
                if qmodel.optype == Just Contigs && qmodel.facontent == contigExampleData && p == Peptides then
                    ( { qmodel | optype = Just Peptides, facontent = peptidesExampleData }, Cmd.none )

                else if qmodel.optype == Just Peptides && qmodel.facontent == peptidesExampleData && p == Contigs then
                    ( { qmodel | optype = Just Contigs, facontent = contigExampleData }, Cmd.none )

                else
                    ( { qmodel | optype = Just p }, Cmd.none )

        UpdateFacontent c -> ifQuery <| \qmodel -> ( { qmodel | facontent = c }, Cmd.none )

        HelpPopover state -> ifQuery <| \qmodel -> ( { qmodel | helpPopoverState = state }, Cmd.none )

        SetExample -> ifQuery <| \qmodel ->
            let
                nc =
                    case qmodel.optype of
                        Nothing ->
                            "?"

                        -- should never happen
                        Just Contigs ->
                            contigExampleData

                        Just Peptides ->
                            peptidesExampleData
            in
            ( { qmodel | facontent = nc }, Cmd.none )

        SubmitData -> case model of -- We cannot using ifQuery because we want to return Loading
            Loading -> ( model, Cmd.none )
            Query qmodel -> (Loading , submitData qmodel )
            Results _ -> ( model, Cmd.none )
        ResultsData r -> case r of
            Ok v -> ( Results v, Cmd.none )
            Err err -> case err of
                Http.BadUrl s -> (Results (APIError ("Bad URL: "++ s)), Cmd.none)
                Http.Timeout  -> (Results (APIError "Timeout"), Cmd.none)
                Http.NetworkError -> (Results (APIError "Network error"), Cmd.none)
                Http.BadStatus s -> (Results (APIError ("Bad status: " ++ String.fromInt s)), Cmd.none)
                Http.BadBody s -> (Results (APIError ("Bad body: " ++ s)), Cmd.none)
        DownloadResults -> case model of
            Results (APIResultOK r) -> ( model, Download.string "macrel.out.tsv" "application/x-gzip" r.rawdata)
            _ -> ( model, Cmd.none )

submitData : QueryModel -> Cmd Msg
submitData model = Http.post
    { url = "http://aws.big-data-biology.org:1188/predict"
    , body = Http.multipartBody
                [ Http.stringPart "dataType" (if model.optype == Just Peptides then "peptides" else "contigs")
                , Http.stringPart "textData" model.facontent
                ]
    , expect = Http.expectJson ResultsData decodeAPIResult
    }

validateFasta : OperationType -> String -> Maybe String
validateFasta p fa =
    if
        String.length fa > 50200
        -- 200 is a little margin
    then
        Just "Input is too large! Only the first 50,000 characters will be analyzed. Run the tool locally to remove any limitations"

    else if
        nrSeqs fa > 1004
        -- 4 is a little margin
    then
        Just "Too many sequences. Only the first 1,000 sequences will will be analyzed. Run the tool locally to remove any limitations"

    else
        case p of
            Peptides ->
                Nothing

            Contigs ->
                Nothing
                -- TODO
                -- validate that it's not AAs


nrSeqs : String -> Int
nrSeqs fa =
    String.filter (\c -> c == '>') fa |> String.length


view : Model -> Browser.Document Msg
view model =
    { title = "AMP Prediction"
    , body =
        [ CDN.stylesheet
        , CDN.fontAwesome
        , Grid.container []
            [ Grid.simpleRow
                [ Grid.col []
                    [ header
                    , Html.hr [] []
                    , intro
                    , Html.hr [] []
                    , viewModel model
                    , Html.hr [] []
                    , outro
                    , Html.hr [] []
                    , footer
                    ]
                ]
            ]
        ]
    }


header : Html Msg
header =
    Grid.simpleRow
        [ Grid.col [] [ Html.h4 [] [ Html.text "Macrel" ] ]
        , Grid.col [] [ Html.a [ href "http://macrel.rtfd.io/" ] [ Html.h4 [] [ Html.text "Docs" ] ] ]
        , Grid.col [] [ Html.a [ href "https://github.com/BigDataBiology/macrel/" ] [ Html.h4 [] [ Html.text "Github" ] ] ]
        ]


intro : Html Msg
intro =
    Alert.simpleInfo []
        [ Html.p [] [ Html.text "If you use macrel in your published work, please cite:" ]
        , Html.blockquote []
            [ Html.p []
                [ Html.em []
                    [ Html.text """
                                    MACREL: antimicrobial peptide screening in genomes and metagenomes. Celio Dias Santos-Junior, Shaojun
                                    Pan, Xing-Ming Zhao, Luis Pedro Coelho. bioRxiv 2019-2020; DOI:"""
                    , Html.a [ href "https://doi.org/10.1101/2019.12.17.880385" ] [ Html.text "10.1101/2019.12.17.880385" ]
                    ]
                ]
            , Html.p [] [ Html.text "The preprint also details the macrel algorithms and presents benchmarking results" ]
            ]
        ]


outro : Html Msg
outro =
    Html.div []
        [ Html.p [] [ Html.text """Macrel uses machine learning to select peptides
    with high probability of being an AMP. Macrel is optimized for higher
    specificity (low rate of false positives).""" ]
        , Html.p [] [ Html.text """Macrel will also classify AMPs into hemolytic and
    non-hemolytic peptides.""" ]
        ]


footer : Html Msg
footer =
    Html.text "Copyright 2019-2020 Macrel authors"

viewModel : Model -> Html Msg
viewModel model = case model of
    Loading -> Html.div []
                    [Html.div []
                        [Spinner.spinner [ Spinner.color Text.primary, Spinner.grow ] [ ]
                        ,Html.p [] [ Html.text "Waiting for results..." ]
                        ,Html.p [] [ Html.text "Normally, it should not take too long, but, for large inputs, you can also run the local version." ]
                        ]
                    ]
    Query qm -> viewQueryModel qm
    Results r -> viewResults r

viewResults r = case r of
    APIError err ->
        Alert.simpleDanger []
            [ Html.p [] [ Html.text "Call to the macrel server failed" ]
            , Html.blockquote []
                [ Html.p [] [ Html.text err ] ]
            ]
    APIResultOK ok -> Html.div []
            [Table.table
                    { options = [ Table.striped, Table.hover ]
                    , thead =  Table.simpleThead
                        [ Table.th [] [ Html.text "Sequence name" ]
                        , Table.th [] [ Html.text "Sequence" ]
                        , Table.th [] [ Html.text "AMP probability" ]
                        ]
                    , tbody = Table.tbody []
                            (List.map (\e ->
                                Table.tr []
                                    [ Table.td [] [ Html.text e.access ]
                                    , Table.td [] [ Html.text e.sequence ]
                                    , Table.td [] [ Html.text <| String.fromFloat e.amp_probability ]
                                    ]) ok.data)
                    }
            ,Html.p [] [ Html.text <| "Prediction with macrel v"++ok.macrelVersion++"." ]
            ,Html.p [] [ Html.text <| "Note that only positive sequences (AMPs) are output."]
            ,Button.button [ Button.primary, Button.onClick DownloadResults ] [ Html.text "Download results table" ]
            ]

viewQueryModel : QueryModel -> Html Msg
viewQueryModel model =
    let
        buttonStyle who active =
            case active of
                Nothing ->
                    [ Button.primary, Button.onClick (SelectOp who) ]

                Just p ->
                    if who == p then
                        [ Button.info, Button.onClick (SelectOp who) ]

                    else
                        [ Button.outlineSecondary, Button.onClick (SelectOp who) ]

        placeholderText =
            case model.optype of
                Nothing ->
                    "Select input type above..."

                Just Contigs ->
                    ">ContigID\nAATACTACTATCTCTCTCTACTATCTACATCATCA...\n"

                Just Peptides ->
                    ">PeptideID\nMEPEPAGAD....\n"

        faerror =
            case model.optype of
                Nothing ->
                    Nothing

                Just p ->
                    validateFasta p model.facontent
    in
    Grid.simpleRow
        [ Grid.col [] <|
            [ Html.h2 [] [ Html.text "Online AMP prediction" ]
            , Html.p []
                [ Html.strong [] [ Html.text "Step 1." ]
                , Html.text " Select mode:"
                ]
            , Grid.simpleRow
                [ Grid.col [] [ Button.button (buttonStyle Contigs model.optype) [ Html.text "Predict from contigs (DNA sequences)" ] ]
                , Grid.col [] [ Button.button (buttonStyle Peptides model.optype) [ Html.text "Predict from peptides (amino acid sequences)" ] ]
                ]
            , Html.p []
                [ Html.text
                    "(The command line tool also supports prediction from short-reads, but this is not available on the webserver)."
                ]
            , case faerror of
                Nothing ->
                    Html.text ""

                Just err ->
                    Alert.simpleWarning [] [ Html.text err ]
            , case model.optype of
                Nothing ->
                    Html.text ""

                Just p ->
                    Form.group []
                        [ Html.label [ for "fasta" ]
                            [ Html.strong [] [ Html.text "Step 2." ]
                            , Html.text <|
                                if p == Contigs then
                                    " Input DNA FASTA "

                                else
                                    " Input Peptides FASTA "
                            , Popover.config
                                (Button.button
                                    [ Button.small
                                    , Button.primary
                                    , Button.attrs <|
                                        Popover.onHover model.helpPopoverState HelpPopover
                                    , Button.attrs <|
                                        Popover.onClick model.helpPopoverState HelpPopover
                                    ]
                                    [ Html.span [ class "fa fa-question-circle" ] [] ]
                                )
                                |> Popover.right
                                |> Popover.titleH4 [] [ Html.text "FASTA format" ]
                                |> Popover.content []
                                    [ Html.text
                                        (case model.optype of
                                            Nothing ->
                                                ""

                                            Just Contigs ->
                                                """
                                                Please provide nucleotides (or change to peptides mode above).
                                                Please avoid contigs containing non-canonical bases, such as N, R or Y."""

                                            Just Peptides ->
                                                """
Peptides submitted to the Macrel prediction should consist of 20 canonical
amino acids and their length should range from 10 to 100 amino acids."""
                                        )
                                    ]
                                |> Popover.view model.helpPopoverState
                            ]
                        , Textarea.textarea <|
                            [ Textarea.id "fasta"
                            , Textarea.rows 10
                            , Textarea.onInput UpdateFacontent
                            , Textarea.attrs [ placeholder placeholderText ]
                            , Textarea.value model.facontent
                            ]
                                ++ (case faerror of
                                        Nothing ->
                                            []

                                        Just _ ->
                                            [ Textarea.danger ]
                                   )
                        , Grid.row [ Row.rightXl ]
                            [ Grid.col [] [ Html.text "" ]
                            , Grid.col [ Col.textAlign Text.alignXsRight ]
                                [ Button.button [ Button.small, Button.outlineSecondary, Button.onClick SetExample ] [ Html.text "Example" ] ]
                            ]
                        , Button.button [ Button.primary, Button.onClick SubmitData ] [ Html.text "Submit" ]
                        ]
            ]
        ]


contigExampleData : String
contigExampleData = """>scaffold2530_2_MH0058
CTTCTGATCTTTACGCAGCATTGTGTGTTTCCACCTTTCAAAAAATTCTCCGTGAACTGC
GCCCTGGGAGTGGTGAAATCCTCCGCGGAACGAAGTCCCGGAATTGCGCACAAATTCACG
TGCTGAACAATTTTACCATAGGAATGTGCGGTTGTAAAGAGAAAAATGCAAAAAATTCCT
TATTTTTATAAAAGGAGCGGGGAAAAGAGGCGGAAAATATTTTTTTGAAAGGGGATTGAC
AGAGAGAAACGGCCGTGTTATCCTAACTGTACTAACACACATAGTACAGTTGGTACAGTT
CGGAGGAACGTTATGAAGGTCATCAAGAAGGTAGTAGCCGCCCTGATGGTGCTGGGAGCA
CTGGCGGCGCTGACGGTAGGCGTGGTTTTGAAGCCGGGCCGGAAAGGAGACGAAACATGA
TGCTGTTTGGTTTTGCGGGGATCGCCGCCATCGTGGGTCTGATTTTTGCCGCTGTTGTTC
TGGTGTCCGTGGCCTTGCAGCCCTGAGAACGGGGCAGATGCAATGAGTACGCTGTTTTTG
CTTGGTATCGCAGGCGCGGTACTGCTGGTTATTTTGCTGACAGCGGTGATCCTGCACCGC
TGATCGAACATTCCTCAGAAAGGAGAGGCACACGTTCTGACATTGAATTACCGGGATTCC
CGTCCCATTTATGAACAGATCAAGGACGGCCTGCGGCGGATGATCGTCACCGGGGCC
>scaffold75334_1_MH0058
ACAGCTTCCTCACCATCAACAGCCACTGCTACGATACCGGCAGGAACAGAGATTGTAGCG
TTATCGGAAGTAAGAACGGTCTCAGCGATTACCTTACCCAAGATATTCGTGATAACTACA
GACTTACCAGCTGCGCCTTGAACGGTTACGGTACCGTTACCGGCTACTACAGAGATACCT
TCTACAGCATCGATTGTTTCGTTATCTGTTGCGATATCATCACCTTGCTCCACATTAAAG
ATCAAAGCATCGTCACCACCTGTATTCATCTCATCGAAATTAGAAGAACGATCATCAGAC
AGAACTAAACAACCATTCTGCATTCTCAACCAAGCCGCATATGTAGGAGCGATGTCACCC
ATAGCAGAATTATTGTAACCAGGAACATGTTTACTCTTCATAGACTCGAACAAGAATGCT
CTATCAGCTTCTACCTCATTAGCGGCAACTTCCTTGTTTACGAAACGCATAGACCAAGTC
ACATACTTATGGTTATCACCAGATAAGATATATTTGTGTGAAACAAATTCATCTTCAGAT
ACTCCAGCCTTCTTAGCCGCAGTCCAAGCATCCTCCTCAGCCTTGTTCAAATCAGCGAAG
TTGATCTTCTCGTTCGGTAAGTTCTTGAACTCATCTCTCAAGATATACAAAGTATCAGCT
ACACGGATAGCTTCCACGAAACCTGCACGATCATATTTCTTCCACATGTAGTCAGCATCT
TGCTCCCCATTTGATAATGTTGACCAACCACATTTATTAGCGAAATCATGGAAATTGATC
AAATATTTACCTCTTTCAAAGCCCGGAACAGCCGGTTTTGCGTGAACGCAATGCCATTTA
TCTGTCGGTTTACCTTCTGCGGTAAAGTGATGGTCATCTTCCGTACAAGGTACGCCTTCA
ACTCCTTCGAAATCGTTACGATCAATAGAGATCAAATATTGAGGCTTGATATTACCAGAA
CCACGGTTTACCCATGCGGTATCAACGATGAATGACAAACCATCCTCAGTCTTATCCGGA
GTATAAATACCTAAGAAGTCAATACCTTCTTTCATGAAGTTCTTATTATTCTCAACCTGC
AAGTATTCTTTACGGTATTTCTCGATAAAACGTAAAGTATCGGCCTTGTCACCTTCATTA
CCTTCAAGTTCAAGAGAACTGAAACGACGGTAAAGCGGAGTGTTGTCCGGTTCGATAGCG
AAAGCAGAAGTACGAGTCTCGCCTAATACTTGATTCTTCAATGTAGCGGCACCGTCATAA
TCGGATACTCCAGCTTTCTGATAACCTAATACATATTTTGTAGCATTAGAATAATTATCA
TATGCAGCATTAACAATCGCATAATAGTGCTTTCCACTGATATAGTTGTTTTCTTTGAAG
AATGCATAATAAGTCGTATAAGATTGCTGATGACCAGTAGCACTAGAACCTACATTAAAC
TTATCTTCCTTATTAACTTTCCATTCATTAAGTTCACCTTTACCATCTTTATAAGAAACC
TCATAAGCAGTTCTCACTAGAGTCTTCAAGCCTTTAATACGATTCTTAGCCACATCATCG
CTAACCTTATAACCGTAAGGGATATCTACAGTCGCAAATATCTTTGAGTTATTATTCCAA
CGCTCAGTCAATGTATCAATTACGAAAGCATCTTTTCCATCCAACACAGTCAACGTAGAG
TCTGTAGATTTAGCGATGTATTTATCCGTAGCATAAGGATGCCAATAGTTAAACGTATAT
TTGTTAACCAACAAAGAATCTTTCTCCAACTTTCTGTAACCTAAATACGGATCAGAAATA
GAAGCTGCCGGAACTTTCTCGAAGAACAAAGAATCTATACCGACAGAGCCATACTCCGCT
GTAAGTTTATCTCCATATACAAACATATAAGAACCACCCTCTGCCTTTCTTAACTGAACA
GTAGAATAAACAGCAGTCTTATATGACTCCATCTGGCCATCACCATCAAAATCCGCATTT
ATAACTTTATCTGCGAATTCACGGTTAGAGATAGTAACCGGAGACACAGCCTTCACTTTA
TCATTACTTGTATTTTTCTTCAATACAACCCATTGATAAGCTGGCATATGAGCAACACTC
TGCTCATCCTCATTCACGGTTGTCCAACGGATAGTACCATTCTCATAGATAGGAGAAGCT
AAATACTGTCCTTGTTTATTCTTGATGAAATAAACACCATCATCAACGGAAGTCTTGGAA
GAACCCTTTTCCTCACATCCGCTAAGACCCAAAGAAATATGAGTGTTCTGGTCCTCCGGA
TCAACTGTCAAAATACAAGTTTCATCTTTAATCAAGTCTTGCAAAGAGACACGCCAGAAC
TCATGCTCGTTAACTGGAGTAGCCGTAACGTGCGTATTCCAATACTTGCCATCATTATTC
CAAGTAACTTTTTTTACATAGATGTATAAGCTATCGCCACTCGGAGAATAGATGAATTTG
AACTGATGTTGAGCACGTAATTCAGAGCTAATAGAACTGTAAGCATCAGCTTTATCCTTT
GCTTTCTCTGTCCAACCGTAAGCTAAGAACTTTGTACCTGTCTCATTCGTATAAGCCGTA
TCAACTTTCAAATAAGCGTCTTTATCCTTTTGCTTGATGAAAAGCCATTTGTTATTATCT
TTATCCTCTGCGATAAACTTCTGCTCATTGAACGGATTCTTTAAGCTAGTACCTTTCACG
TCCGGAGTGAAAGTCAATTGTACTCCAGCCTTGTTATCTTGAAGAAGACCCAACTTCGTA
TTTACTTGATCTTCGCTCAATGCGATTTGTGCTGCGCCAACCAAAGCAAAGTTAGTCACA
TCAGCGGCGTTTGAAGTGGCATCTATTTGATTAGCACCCCACTTGGCAACCTTAACAGCT
CCGGTAGTAGGATCCGCTTTCAAACCAACAATTGAGTCCGTTGAGAAATAAGAATACAAA
GGTCTCTTTTCTTCCAAATCCTTGTATGAGCGAGAGAATGCCCAACCTGCGATCTCACCA
CCTAAAACAGGTTTCCAAGCACCATTCGTACCATTCTCAGTCTTCTCATGGCCAGCCATT
GTCAAATCCAACATAGTTCCAGACAATTTATTCTGGAAGTCATAAATAGGAGCTTGACCT
TGATTATAATTAGAGACAGAAACACACCACAATGTAGCCTCTAAGTTATTTTTAGCTTCG
CTTGCACTATAAACACGTAGTTCATAATCACCTGTTCCACGATTTAGCTCCATCGCAAGA
TAAGCAGGAGTAGTGCCATCCATGACCTTCAACTGATAAAGACCAGAATTAGCTCCCTCC
TTCAAACCGCCTAAACGCCATTCTTGACCCAATACAGTTTCTGGGTCTACTCGACTTGGT
GTAGTCTGTGCATTAACAGACATAACACTTAACAGTGCCATACCTGCCAAAAGAGTAGAA
AACT"""

peptidesExampleData : String
peptidesExampleData = """>AP00002|AMP
YVPLPNVPQPGRRPFPTFPGQGPFNPKIKWPQGY
>AP00007|AMP
GNNRPVYIPQPRPPHPRL
>P20491|NAMP
MISAVILFLLLLVEQAAALGEPQLCYILDAVLFLYGIVLTLLYCRLKIQVRKAAIASREKADAVYTGLNTRSQETYETLKHEKPPQ
>P35109|NAMP
MVDDPNKVWPTGLTIAESEELHKHVIDGSRIFVAIAIVAHFLAYVYSPWLH
>P19962|NAMP
DSDSAQNLIG"""
