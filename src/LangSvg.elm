module LangSvg where
-- module LangSvg (valToHtml, valToIndexedTree, printIndexedTree) where

import Html
import Html.Attributes as HA
import Svg
import Svg.Attributes as A
import VirtualDom

-- in Svg.elm:
--   type alias Svg = VirtualDom.Node
--   type alias Attribute = VirtualDom.Property

-- in Html.elm:
--   type alias Html = VirtualDom.Node

import Debug
import Set
import String
import Char
import Dict exposing (Dict)
import ColorNum

import Lang exposing (..)
import Utils

------------------------------------------------------------------------------

-- TODO upgrade to:
-- http://package.elm-lang.org/packages/evancz/elm-svg/2.0.0/Svg

attr = VirtualDom.attribute
svg  = Svg.svgNode

-- TODO probably want to factor HTML attributes and SVG attributes into
-- records rather than lists of lists of ...

valToHtml : Int -> Int -> Val -> Html.Html
valToHtml w h v =
  let (VList vs) = v.v_ in
  case List.map .v_ vs of
    [VBase (String "svg"), VList vs1, VList vs2] ->
      let wh = [numAttrToVal "width" w, numAttrToVal "height" h] in
      let v' = vList [vStr "svg", vList (wh ++ vs1), vList vs2] in
      compileValToNode v'
        -- NOTE: not checking if width/height already in vs1

compileValToNode : Val -> VirtualDom.Node
compileValToNode v = case v.v_ of
  VList vs ->
    case List.map .v_ vs of
      [VBase (String "TEXT"), VBase (String s)] -> VirtualDom.text s
      [VBase (String f), VList vs1, VList vs2] ->
        (svg f) (compileAttrVals vs1) (compileNodeVals vs2)

compileNodeVals : List Val -> List Svg.Svg
compileNodeVals = List.map compileValToNode

compileAttrVals : List Val -> List Svg.Attribute
compileAttrVals = List.map (uncurry compileAttr << valToAttr)

compileAttrs    : List Attr -> List Svg.Attribute
compileAttrs    = List.map (uncurry compileAttr)

compileAttr : String -> AVal -> Svg.Attribute
compileAttr k v = (attr k) (strAVal v)

numAttrToVal a i =
  vList [vBase (String a), vConst (toFloat i, dummyTrace)]

type alias AVal = { av_ : AVal_, vtrace : VTrace }

type AVal_
  = ANum NumTr
  | AString String
  | APoints (List Point)
  | ARgba Rgba
  | AColorNum NumTr -- Utils.numToColor [0,500)
  | APath2 (List PathCmd, PathCounts)
  | ATransform (List TransformCmd)

-- these versions are for when the VTrace doesn't matter
aVal          = flip AVal [-1]
aNum          = aVal << ANum
aString       = aVal << AString
aTransform    = aVal << ATransform
aColorNum     = aVal << AColorNum
aPoints       = aVal << APoints
aPath2        = aVal << APath2

maxColorNum   = 500
clampColorNum = Utils.clamp 0 (maxColorNum - 1)

type alias Point = (NumTr, NumTr)
type alias Rgba  = (NumTr, NumTr, NumTr, NumTr)

type PathCmd
  = CmdZ   Cmd
  | CmdMLT Cmd IdPoint
  | CmdHV  Cmd NumTr
  | CmdC   Cmd IdPoint IdPoint IdPoint
  | CmdSQ  Cmd IdPoint IdPoint
  | CmdA   Cmd NumTr NumTr NumTr NumTr NumTr IdPoint

type TransformCmd
  = Rot NumTr NumTr NumTr

type alias PathCounts = {numPoints : Int}

type alias Cmd = String -- single uppercase/lowercase letter

type alias IdPoint = (Maybe Int, Point)

-- toNum    (ANum (i,_)) = i
-- toNumTr  (ANum (i,t)) = (i,t)

strValOfAVal = strVal << valOfAVal

x `expectedButGot` s = errorMsg <| "expected " ++ x ++", but got: " ++ s

-- temporary way to ignore numbers specified as strings (also see Sync)

toNum : AVal -> Num
toNum a = case a.av_ of
  ANum (n,_) -> n
  AString s  ->
    case String.toFloat s of
      Ok n -> n
      _    -> "a number" `expectedButGot` strValOfAVal a
  _        -> "a number" `expectedButGot` strValOfAVal a

toNumTr a = case a.av_ of
  ANum (n,t) -> (n,t)
  AColorNum (n,t) -> (n,t)
  AString s  ->
    case String.toFloat s of
      Ok n -> (n, dummyTrace)
      _    -> "a number" `expectedButGot` strValOfAVal a
  _        -> "a number" `expectedButGot` strValOfAVal a

toPoints a = case a.av_ of
  APoints pts -> pts
  _           -> "a list of points" `expectedButGot` strValOfAVal a

toPath : AVal -> (List PathCmd, PathCounts)
toPath a = case a.av_ of
  APath2 p -> p
  _        -> "path commands" `expectedButGot` strValOfAVal a

toTransformRot a = case a.av_ of
  ATransform [Rot n1 n2 n3] -> (n1,n2,n3)
  _                         -> "transform commands" `expectedButGot` strValOfAVal a

-- TODO will need to change AVal also
--   and not insert dummy VTraces (using the v* functions)

valToAttr v = case v.v_ of
  VList [v1,v2] -> case (v1.v_, v2.v_) of
    (VBase (String k), v2_) ->
     -- NOTE: Elm bug? undefined error when shadowing k (instead of choosing k')
     let (k',av_) =
      case (k, v2_) of
        ("points", VList vs)    -> (k, APoints <| List.map valToPoint vs)
        ("fill", VList vs)      -> (k, ARgba <| valToRgba vs)
        ("fill", VConst it)     -> (k, AColorNum it)
        ("stroke", VList vs)    -> (k, ARgba <| valToRgba vs)
        ("d", VList vs)         -> (k, APath2 (valsToPath2 vs))
        ("transform", VList vs) -> (k, ATransform (valsToTransform vs))
        (_, VConst it)          -> (k, ANum it)
        (_, VBase (String s))   -> (k, AString s)
     in
     (k', AVal av_ v2.vtrace)

        -- TODO "stroke" AColorNum

valToPoint v = case v.v_ of
  VList vs -> case List.map .v_ vs of
    [VConst x, VConst y] -> (x,y)
    _                    -> "a point" `expectedButGot` strVal v
  _                      -> "a point" `expectedButGot` strVal v

pointToVal (x,y) = (vList [vConst x, vConst y])

valToRgba vs = case List.map .v_ vs of
  [VConst r, VConst g, VConst b, VConst a] -> (r,g,b,a)
  _                                        -> "rgba" `expectedButGot` strVal (vList vs)

rgbaToVal (r,g,b,a) = [vConst r, vConst g, vConst b, vConst a]

strPoint (x_,y_) =
  let [x,y] = List.map fst [x_,y_] in
  toString x ++ "," ++ toString y

strRgba (r_,g_,b_,a_) =
  strRgba_ (List.map fst [r_,g_,b_,a_])

strRgba_ rgba =
  "rgba" ++ Utils.parens (Utils.commas (List.map toString rgba))

strAVal : AVal -> String
strAVal a = case a.av_ of
  AString s -> s
  ANum it   -> toString (fst it)
  APoints l -> Utils.spaces (List.map strPoint l)
  ARgba tup -> strRgba tup
  APath2 p  -> strAPath2 (fst p)
  ATransform l -> Utils.spaces (List.map strTransformCmd l)
  AColorNum n ->
    -- slight optimization:
    strRgba_ (ColorNum.convert (fst n))
    -- let (r,g,b) = Utils.numToColor maxColorNum (fst n) in
    -- strRgba_ [r,g,b,1]

valOfAVal : AVal -> Val
valOfAVal a = flip Val a.vtrace <| case a.av_ of
  AString s    -> VBase (String s)
  ANum it      -> VConst it
  APoints l    -> VList (List.map pointToVal l)
  ARgba tup    -> VList (rgbaToVal tup)
  APath2 p     -> VList (List.concatMap valsOfPathCmd (fst p))
  AColorNum nt -> VConst nt

valsOfPathCmd c =
  Debug.crash "restore valsOfPathCmd"
{-
  let fooPt (_,(x,y)) = [vConst x, vConst y] in
  case c of
    CmdZ   s              -> vStr s :: []
    CmdMLT s pt           -> vStr s :: fooPt pt
    CmdHV  s n            -> vStr s :: [vConst n]
    CmdC   s pt1 pt2 pt3  -> vStr s :: List.concatMap fooPt [pt1,pt2,pt3]
    CmdSQ  s pt1 pt2      -> vStr s :: List.concatMap fooPt [pt1,pt2]
    CmdA   s a b c d e pt -> vStr s :: List.map vConst [a,b,c,d,e] ++ fooPt pt
-}

valOfAttr (k,a) = vList [vBase (String k), valOfAVal a]
  -- no VTrace to preserve...

-- https://developer.mozilla.org/en-US/docs/Web/SVG/Tutorial/Paths
-- http://www.w3schools.com/svg/svg_path.asp
--
-- NOTES:
--  . using different representation of points in d than in points
--    to make it less verbose and easier to copy-and-paste raw SVG examples
--  . looks like commas are optional

valsToPath2 = valsToPath2_ {numPoints = 0}

valsToPath2_ : PathCounts -> List Val -> (List PathCmd, PathCounts)
valsToPath2_ counts vs = case vs of
  [] -> ([], counts)
  v::vs' ->
    let (VBase (String cmd)) = v.v_ in
    if | matchCmd cmd "Z" -> CmdZ cmd +++ valsToPath2_ counts vs'
       | matchCmd cmd "MLT" ->
           let ([x,y],vs'') = projConsts 2 vs' in
           let (counts',[pt]) = addIdPoints cmd counts [(x,y)] in
           CmdMLT cmd pt +++ valsToPath2_ counts' vs''
       | matchCmd cmd "HV" ->
           let ([i],vs'') = projConsts 1 vs' in
           CmdHV cmd i +++ valsToPath2_ counts vs''
       | matchCmd cmd "C" ->
           let ([x1,y1,x2,y2,x,y],vs'') = projConsts 6 vs' in
           let (counts',[pt1,pt2,pt3]) = addIdPoints cmd counts [(x1,y1),(x2,y2),(x,y)] in
           CmdC cmd pt1 pt2 pt3 +++ valsToPath2_ counts' vs''
       | matchCmd cmd "SQ" ->
           let ([x1,y1,x,y],vs'') = projConsts 4 vs' in
           let (counts',[pt1,pt2]) = addIdPoints cmd counts [(x1,y1),(x,y)] in
           CmdSQ cmd pt1 pt2 +++ valsToPath2_ counts' vs''
       | matchCmd cmd "A" ->
           let ([rx,ry,axis,flag,sweep,x,y],vs'') = projConsts 7 vs' in
           let (counts',[pt]) = addIdPoints cmd counts [(x,y)] in
           CmdA cmd rx ry axis flag sweep pt +++ valsToPath2_ counts' vs''

x +++ (xs,stuff) = (x::xs, stuff)

addIdPoints : Cmd -> PathCounts -> List Point -> (PathCounts, List IdPoint)
addIdPoints cmd counts pts =
  let [c] = String.toList cmd in
  if | Char.isLower c -> (counts, List.map ((,) Nothing) pts)
     | Char.isUpper c ->
         let (counts',l) =
           List.foldl (\pt (acc1,acc2) ->
             let nextId = 1 + acc1.numPoints in
             let acc1'  = {acc1 | numPoints <- nextId} in
             let acc2'  = (Just nextId, pt) :: acc2 in
             (acc1', acc2')) (counts, []) pts
         in
         (counts', List.reverse l)

strAPath2 =
  let strPt (_,(it,jt)) = toString (fst it) ++ " " ++ toString (fst jt) in
  let strNum (n,_) = toString n in

  let strPathCmd c = case c of
    CmdZ   s              -> s
    CmdMLT s pt           -> Utils.spaces [s, strPt pt]
    CmdHV  s n            -> Utils.spaces [s, strNum n]
    CmdC   s pt1 pt2 pt3  -> Utils.spaces (s :: List.map strPt [pt1,pt2,pt3])
    CmdSQ  s pt1 pt2      -> Utils.spaces (s :: List.map strPt [pt1,pt2])
    CmdA   s a b c d e pt ->
      Utils.spaces (s :: List.map strNum [a,b,c,d,e] ++ [strPt pt])
  in
  Utils.spaces << List.map strPathCmd

projConsts k vs =
  case (k == 0, vs) of
    (True, _)       -> ([], vs)
    (False, v::vs') ->
      case v.v_ of
        VConst it ->
          let (l1,l2) = projConsts (k-1) vs' in
          (it::l1, l2)

matchCmd cmd s =
  let [c] = String.toList cmd in
  let cs  = String.toList s in
  List.member c (cs ++ List.map Char.toLower cs)

-- transform commands

valsToTransform : List Val -> List TransformCmd
valsToTransform = List.map valToTransformCmd

valToTransformCmd v = case v.v_ of
  VList vs1 -> case List.map .v_ vs1 of
    (VBase (String k) :: vs) ->
      case (k, vs) of
        ("rotate", [VConst n1, VConst n2, VConst n3]) -> Rot n1 n2 n3
        _ -> "a transform command" `expectedButGot` strVal v
    _     -> "a transform command" `expectedButGot` strVal v
  _       -> "a transform command" `expectedButGot` strVal v

strTransformCmd cmd = case cmd of
  Rot n1 n2 n3 ->
    let nums = List.map (toString << fst) [n1,n2,n3] in
    "rotate" ++ Utils.parens (Utils.spaces nums)


{- old way of doing things with APath...

valToPath = Utils.spaces << valToPath_

valToPath_ vs =
  let pt (i,_) (j,_) = toString i ++ " " ++ toString j in
  case vs of
    [] -> []
    VBase (String cmd) :: vs' ->
      if | matchCmd cmd "Z" -> cmd :: valToPath_ vs'
         | matchCmd cmd "MLT" ->
             let ([sx,sy],vs'') = projConsts 2 vs' in
             cmd :: pt sx sy :: valToPath_ vs''
         | matchCmd cmd "HV" ->
             let ([i],vs'') = projConsts 1 vs' in
             cmd :: toString i :: valToPath_ vs''
         | matchCmd cmd "C" ->
             let ([x1,y1,x2,y2,x,y],vs'') = projConsts 6 vs' in
             let pts = String.join " , " [pt x1 y1, pt x2 y2, pt x y] in
             cmd :: pts :: valToPath_ vs''
         | matchCmd cmd "SQ" ->
             let ([x1,y1,x,y],vs'') = projConsts 4 vs' in
             let pts = String.join " , " [pt x1 y1, pt x y] in
             cmd :: pts :: valToPath_ vs''
         | matchCmd cmd "A" ->
             let (ns,vs'') = projConsts 7 vs' in
             let blah = Utils.spaces (List.map toString ns) in
             cmd :: blah :: valToPath_ vs'' -- not worrying about commas

-}


------------------------------------------------------------------------------

type alias ShapeKind = String
type alias NodeId = Int
type alias IndexedTree = Dict NodeId IndexedTreeNode
type alias Attr = (String, AVal)
type IndexedTreeNode
  = TextNode String
  | SvgNode ShapeKind (List Attr) (List NodeId)
type alias RootedIndexedTree = (NodeId, IndexedTree)

children n = case n of {TextNode _ -> []; SvgNode _ _ l -> l}

emptyTree : RootedIndexedTree
emptyTree = valToIndexedTree <| vList [vBase (String "svg"), vList [], vList []]

-- TODO use options for better error messages

valToIndexedTree : Val -> RootedIndexedTree
valToIndexedTree v =
  let (nextId,tree) = valToIndexedTree_ v (1, Dict.empty) in
  let rootId = nextId - 1 in
  (rootId, tree)

valToIndexedTree_ v (nextId, d) = case v.v_ of

  VList vs -> case List.map .v_ vs of

    [VBase (String "TEXT"), VBase (String s)] ->
      (1 + nextId, Dict.insert nextId (TextNode s) d)

    [VBase (String kind), VList vs1, VList vs2] ->
      let processChild vi (a_nextId, a_graph , a_children) =
        let (a_nextId',a_graph') = valToIndexedTree_ vi (a_nextId, a_graph) in
        let a_children'          = (a_nextId' - 1) :: a_children in
        (a_nextId', a_graph', a_children') in
      let (nextId',d',children) = List.foldl processChild (nextId,d,[]) vs2 in
      let node = SvgNode kind (List.map valToAttr vs1) (List.reverse children) in
      (1 + nextId', Dict.insert nextId' node d')

    _ ->
      "an SVG node" `expectedButGot` strVal v

  _ ->
    "an SVG node" `expectedButGot` strVal v

printIndexedTree : Val -> String
printIndexedTree = valToIndexedTree >> snd >> strEdges

strEdges : IndexedTree -> String
strEdges =
     Dict.toList
  >> List.map (\(i,n) ->
       let l = List.map toString (children n) in
       toString i ++ " " ++ Utils.braces (Utils.spaces l))
  >> Utils.lines


------------------------------------------------------------------------------
-- Printing to SVG format

printSvg : RootedIndexedTree -> String
printSvg (rootId, tree) = printNode 0 tree rootId

printNode k slate i =
  case Utils.justGet i slate of
    TextNode s -> s
    SvgNode kind l1 [] ->
      let l1' = addAttrs kind l1 in
      Utils.delimit "<" ">" (kind ++ printAttrs l1') ++
      Utils.delimit "</" ">" kind
    SvgNode kind l1 l2 ->
      let l1' = addAttrs kind l1 in
      Utils.delimit "<" ">" (kind ++ printAttrs l1') ++ "\n" ++
      printNodes (k+1) slate l2 ++ "\n" ++
      tab k ++ Utils.delimit "</" ">" kind

printNodes k slate =
  Utils.lines << List.map ((++) (tab k) << printNode k slate)

printAttrs l = case l of
  [] -> ""
  _  -> " " ++ Utils.spaces (List.map printAttr l)

printAttr (k,v) =
  k ++ "=" ++ Utils.delimit "'" "'" (strAVal v)

addAttrs kind attrs =
  if | kind == "svg" -> ("xmlns", aString "http://www.w3.org/2000/svg") :: attrs
     | otherwise     -> attrs


------------------------------------------------------------------------------
-- Zones

type alias Zone = String

-- NOTE: would like to use only the following definition, but datatypes
-- aren't comparable... so using Strings for storing in dictionaries, but
-- using the following for pattern-matching purposes

type RealZone = Z String | ZPoint Int | ZEdge Int

addi s i = s ++ toString i

realZoneOf s =
  Maybe.withDefault (Z s) (toZPoint s `Utils.plusMaybe` toZEdge s)

toZPoint s =
  Utils.mapMaybe
    (ZPoint << Utils.fromOk_ << String.toInt)
    (Utils.munchString "Point" s)

toZEdge s =
  Utils.mapMaybe
    (ZEdge << Utils.fromOk_ << String.toInt)
    (Utils.munchString "Edge" s)

-- TODO perhaps define Interface callbacks here

zones = [
    ("svg", [])
  , ("circle",
      [ ("Interior", ["cx", "cy"])
      , ("Edge", ["r"])
      ])
  , ("ellipse",
      [ ("Interior", ["cx", "cy"])
      , ("Edge", ["rx", "ry"])
      ])
  , ("rect",
      [ ("Interior", ["x", "y"])
      , ("TopLeftCorner", ["x", "y", "width", "height"])
      , ("TopRightCorner", ["y", "width", "height"])
      , ("BotRightCorner", ["width", "height"])
      , ("BotLeftCorner", ["x", "width", "height"])
      , ("LeftEdge", ["x", "width"])
      , ("TopEdge", ["y", "height"])
      , ("RightEdge", ["width"])
      , ("BotEdge", ["height"])
      ])
  , ("line",
      [ ("Point1", ["x1", "y1"])
      , ("Point2", ["x2", "y2"])
      , ("Edge", ["x1", "y1", "x2", "y2"])
      ])
  -- TODO
  , ("g", [])
  , ("text", [])
  , ("tspan", [])

  -- symptom of the Sync.Dict0 type. see Sync.nodeToAttrLocs_.
  , ("DUMMYTEXT", [])

  -- NOTE: these are computed in Sync.getZones
  -- , ("polygon", [])
  -- , ("polyline", [])
  -- , ("path", [])
  ]


------------------------------------------------------------------------------

dummySvgNode =
  let zero = aNum (0, dummyTrace) in
  SvgNode "circle" (List.map (\k -> (k, zero)) ["cx","cy","r"]) []

-- TODO break up and move slateToVal here
dummySvgVal =
  let zero = vConst (0, dummyTrace) in
  let attrs = vList <| List.map (\k -> vList [vStr k, zero]) ["cx","cy","r"] in
  let children = vList [] in
  vList [vStr "circle", attrs, children]
