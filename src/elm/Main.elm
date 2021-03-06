module Main exposing (init, update, view, Model, Msg)

{-| The content editor client top module.

@docs init, update, subscriptions, view, Model, Msg

-}

import AWS.Auth as Auth
import AuthAPI
import Browser
import Config exposing (config)
import Css
import Css.Global
import Grid
import Html
import Html.Styled exposing (div, form, h4, img, label, span, styled, text, toUnstyled)
import Html.Styled.Attributes exposing (for, name, src)
import Html.Styled.Events exposing (onClick, onInput)
import Process
import Responsive
import Styles exposing (lg, md, sm, xl)
import Task
import TheSett.Buttons as Buttons
import TheSett.Cards as Cards
import TheSett.Debug
import TheSett.Laf as Laf exposing (devices, fonts, responsiveMeta, wrapper)
import TheSett.Textfield as Textfield
import Update3
import UpdateUtils exposing (lift)
import ViewUtils


{-| The content editor program model.
-}
type Model
    = Error String
    | Restoring InitializedModel
    | Initialized InitializedModel


type alias InitializedModel =
    { laf : Laf.Model
    , auth : Auth.Model
    , session : AuthAPI.Status Auth.AuthExtensions Auth.Challenge
    , username : String
    , password : String
    , passwordVerify : String
    }


{-| The content editor program top-level message types.
-}
type Msg
    = LafMsg Laf.Msg
    | AuthMsg Auth.Msg
    | InitialTimeout
    | LogIn
    | LogOut
    | RespondWithNewPassword
    | TryAgain
    | Refresh
    | UpdateUsername String
    | UpdatePassword String
    | UpdatePasswordVerificiation String



-- Initialization


{-| Initializes the application state by setting it to the default Auth state
of LoggedOut.
Requests that an Auth refresh be performed to check what the current
authentication state is, as the application may be able to re-authenticate
from a refresh token held as a cookie, without needing the user to log in.
-}
init : flags -> ( Model, Cmd Msg )
init _ =
    let
        authInitResult =
            Auth.api.init
                { clientId = "2gr0fdlr647skqqghtau04vuct"
                , region = "us-east-1"
                , userIdentityMapping =
                    Just
                        { userPoolId = "us-east-1_LzM42GX6Q"
                        , identityPoolId = "us-east-1:fb4d5209-33b1-46e2-923a-8aa206d5c7aa"
                        , accountId = "345745834314"
                        }
                }
    in
    case authInitResult of
        Ok authInit ->
            ( Initialized
                { laf = Laf.init
                , auth = authInit
                , session = AuthAPI.LoggedOut
                , username = ""
                , password = ""
                , passwordVerify = ""
                }
            , Process.sleep 1000 |> Task.perform (always InitialTimeout)
            )

        Err errMsg ->
            ( Error errMsg, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update action model =
    case model of
        Error _ ->
            ( model, Cmd.none )

        Restoring initModel ->
            updateInitialized action initModel
                |> Tuple.mapFirst Initialized

        Initialized initModel ->
            updateInitialized action initModel
                |> Tuple.mapFirst Initialized


updateInitialized : Msg -> InitializedModel -> ( InitializedModel, Cmd Msg )
updateInitialized action model =
    case Debug.log "msg" action of
        LafMsg lafMsg ->
            Laf.update LafMsg lafMsg model.laf
                |> Tuple.mapFirst (\laf -> { model | laf = laf })

        AuthMsg msg ->
            Update3.lift .auth (\x m -> { m | auth = x }) AuthMsg Auth.api.update msg model
                |> Update3.evalMaybe (\status -> \nextModel -> ( { nextModel | session = status }, Cmd.none )) Cmd.none

        InitialTimeout ->
            ( model, Auth.api.refresh |> Cmd.map AuthMsg )

        LogIn ->
            ( model, Auth.api.login { username = model.username, password = model.password } |> Cmd.map AuthMsg )

        RespondWithNewPassword ->
            case model.password of
                "" ->
                    ( model, Cmd.none )

                newPassword ->
                    ( model, Auth.api.requiredNewPassword newPassword |> Cmd.map AuthMsg )

        TryAgain ->
            ( clear model, Auth.api.unauthed |> Cmd.map AuthMsg )

        LogOut ->
            ( clear model, Auth.api.logout |> Cmd.map AuthMsg )

        Refresh ->
            ( model, Auth.api.refresh |> Cmd.map AuthMsg )

        UpdateUsername str ->
            ( { model | username = str }, Cmd.none )

        UpdatePassword str ->
            ( { model | password = str }, Cmd.none )

        UpdatePasswordVerificiation str ->
            ( { model | passwordVerify = str }, Cmd.none )


clear : InitializedModel -> InitializedModel
clear model =
    { model | username = "", password = "", passwordVerify = "" }



-- View


paperWhite =
    Css.rgb 248 248 248


global : List Css.Global.Snippet
global =
    [ Css.Global.each
        [ Css.Global.html ]
        [ Css.height <| Css.pct 100
        , Responsive.deviceStyle devices
            (\device ->
                let
                    headerPx =
                        Responsive.rhythm 9.5 device
                in
                Css.property "background" <|
                    "linear-gradient(rgb(120, 116, 120) 0%, "
                        ++ String.fromFloat headerPx
                        ++ "px, rgb(225, 212, 214) 0px, rgb(208, 212, 214) 100%)"
            )
        ]
    ]


{-| Top level view function.
-}
view : Model -> Browser.Document Msg
view model =
    { title = "Auth Elm Example"
    , body = [ body model ]
    }


body : Model -> Html.Html Msg
body model =
    styledBody model
        |> toUnstyled


styledBody : Model -> Html.Styled.Html Msg
styledBody model =
    let
        innerView =
            [ responsiveMeta
            , fonts
            , Laf.style devices
            , Css.Global.global global
            , case model of
                Error errMsg ->
                    errorView errMsg

                Restoring initModel ->
                    initialView

                Initialized initModel ->
                    initializedView initModel
            ]

        debugStyle =
            Css.Global.global <|
                TheSett.Debug.global Laf.devices
    in
    div [] innerView


errorView errMsg =
    framing <|
        [ card "images/data_center-large.png"
            "Initialization Error"
            [ text ("App failed to initialize: " ++ errMsg) ]
            []
            devices
        ]


initializedView model =
    case model.session of
        AuthAPI.LoggedOut ->
            loginView model

        AuthAPI.Failed ->
            notPermittedView model

        AuthAPI.LoggedIn state ->
            authenticatedView model state

        AuthAPI.Challenged Auth.NewPasswordRequired ->
            requiresNewPasswordView model


initialView : Html.Styled.Html Msg
initialView =
    framing <|
        [ card "images/data_center-large.png"
            "Attempting to Restore"
            [ text "Attempting to restore authentication using a local refresh token." ]
            []
            devices
        ]


loginView : { a | laf : Laf.Model, username : String, password : String } -> Html.Styled.Html Msg
loginView model =
    framing <|
        [ card "images/data_center-large.png"
            "Log In"
            [ form []
                [ Textfield.text
                    LafMsg
                    [ 1 ]
                    model.laf
                    [ Textfield.value model.username ]
                    [ onInput UpdateUsername
                    ]
                    [ text "Username" ]
                    devices
                , Textfield.password
                    LafMsg
                    [ 2 ]
                    model.laf
                    [ Textfield.value model.password
                    ]
                    [ onInput UpdatePassword
                    ]
                    [ text "Password" ]
                    devices
                ]
            ]
            [ Buttons.button [] [ onClick LogIn ] [ text "Log In" ] devices
            ]
            devices
        ]


notPermittedView : { a | laf : Laf.Model, username : String, password : String } -> Html.Styled.Html Msg
notPermittedView model =
    framing <|
        [ card "images/data_center-large.png"
            "Not Authorized"
            [ form []
                [ Textfield.text
                    LafMsg
                    [ 1 ]
                    model.laf
                    [ Textfield.disabled
                    , Textfield.value model.username
                    ]
                    [ onInput UpdateUsername
                    ]
                    [ text "Username" ]
                    devices
                , Textfield.password
                    LafMsg
                    [ 2 ]
                    model.laf
                    [ Textfield.disabled
                    , Textfield.value model.password
                    ]
                    [ onInput UpdatePassword
                    ]
                    [ text "Password" ]
                    devices
                ]
            ]
            [ Buttons.button [] [ onClick TryAgain ] [ text "Try Again" ] devices ]
            devices
        ]


authenticatedView : { a | username : String, auth : Auth.Model } -> { scopes : List String, subject : String } -> Html.Styled.Html Msg
authenticatedView model user =
    let
        maybeAWSCredentials =
            Auth.api.getAWSCredentials model.auth
                |> Debug.log "credentials"

        credentialsView =
            case maybeAWSCredentials of
                Just creds ->
                    [ Html.Styled.li []
                        (text "With AWS access credentials."
                            :: Html.Styled.br [] []
                            :: []
                        )
                    ]

                Nothing ->
                    []
    in
    framing <|
        [ card "images/data_center-large.png"
            "Authenticated"
            [ Html.Styled.ul []
                (List.append
                    [ Html.Styled.li []
                        [ text "Logged In As:"
                        , Html.Styled.br [] []
                        , text model.username
                        ]
                    , Html.Styled.li []
                        [ text "With Id:"
                        , Html.Styled.br [] []
                        , text user.subject
                        ]
                    , Html.Styled.li []
                        (text "With Permissions:"
                            :: Html.Styled.br [] []
                            :: permissionsToChips user.scopes
                        )
                    ]
                    credentialsView
                )
            ]
            [ Buttons.button [] [ onClick LogOut ] [ text "Log Out" ] devices
            , Buttons.button [] [ onClick Refresh ] [ text "Refresh" ] devices
            ]
            devices
        ]


requiresNewPasswordView : { a | laf : Laf.Model, password : String, passwordVerify : String } -> Html.Styled.Html Msg
requiresNewPasswordView model =
    framing <|
        [ card "images/data_center-large.png"
            "New Password Required"
            [ form []
                [ Textfield.password
                    LafMsg
                    [ 1 ]
                    model.laf
                    [ Textfield.value model.password ]
                    [ onInput UpdatePassword
                    ]
                    [ text "Password" ]
                    devices
                , Textfield.password
                    LafMsg
                    [ 2 ]
                    model.laf
                    [ Textfield.value model.passwordVerify
                    ]
                    [ onInput UpdatePasswordVerificiation
                    ]
                    [ text "Password Confirmation" ]
                    devices
                ]
            ]
            [ Buttons.button [] [ onClick RespondWithNewPassword ] [ text "Set Password" ] devices
            ]
            devices
        ]


framing : List (Html.Styled.Html Msg) -> Html.Styled.Html Msg
framing innerHtml =
    styled div
        [ Responsive.deviceStyle devices
            (\device -> Css.marginTop <| Responsive.rhythmPx 3 device)
        ]
        []
        [ Grid.grid
            [ sm [ Grid.columns 12 ] ]
            []
            [ Grid.row
                [ sm [ Grid.center ] ]
                []
                [ Grid.col
                    []
                    []
                    innerHtml
                ]
            ]
            devices
        ]


card :
    String
    -> String
    -> List (Html.Styled.Html Msg)
    -> List (Html.Styled.Html Msg)
    -> Responsive.ResponsiveStyle
    -> Html.Styled.Html Msg
card imageUrl title cardBody controls devices =
    Cards.card
        [ sm
            [ Styles.styles
                [ Css.maxWidth <| Css.vw 100
                , Css.minWidth <| Css.px 310
                , Css.backgroundColor <| paperWhite
                ]
            ]
        , md
            [ Styles.styles
                [ Css.maxWidth <| Css.px 420
                , Css.minWidth <| Css.px 400
                , Css.backgroundColor <| paperWhite
                ]
            ]
        ]
        []
        [ Cards.image
            [ Styles.height 6
            , sm [ Cards.src imageUrl ]
            ]
            []
            [ styled div
                [ Css.position Css.relative
                , Css.height <| Css.pct 100
                ]
                []
                []
            ]
        , Cards.title title
        , Cards.body cardBody
        , Cards.controls controls
        ]
        devices


permissionsToChips : List String -> List (Html.Styled.Html Msg)
permissionsToChips permissions =
    List.map
        (\permission ->
            Html.Styled.span [ Html.Styled.Attributes.class "mdl-chip mdl-chip__text" ]
                [ text permission ]
        )
        permissions
