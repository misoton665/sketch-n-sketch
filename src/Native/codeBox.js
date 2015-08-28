// This is the JavaScript interface between CodeBox.elm and ace.js.
//
// Relevant Ports:
//   aceInTheHole -- Is where new (partial) Models to be rendered come from
//   theTurn      -- Is where what become Events for things like code updates go
//

// For convenience, the page controller is here
var runtime = Elm.fullscreen(Elm.Main, { 
    theTurn : { evt : "init"
              , strArg : "" 
              , cursorArg : { row : 0 , column : 0 }
              , selectionArg : []
              }
});

window.oncrash = function(msg, url, linenumber) {
  var s = '';
  s += 'We crashed... Sorry! Hit OK to restart.\n\n';
  s += 'Error message: ' + msg + '\n\n';
  s += 'The JS error console may contain more info.';
  alert(s);
  location.reload();
}

var Range = ace.require('ace/range').Range

//So we can dynamically add CSS classes, which is needed to style the markers
//Generally only touches the DOM to add new ones if absolutely needed
var style = document.createElement('style');
style.id = "autogenerated_css_classes";
style.type = 'text/css';
document.getElementsByTagName('head')[0].appendChild(style);
var classDict = {};

function makeCSSClass(colorStr) {
    var autogenName = ".autogenerated_class_" + colorStr
    if (!(classDict.hasOwnProperty(autogenName))) {
        style.innerHTML = style.innerHTML 
                            + ".ace_marker-layer "
                            + autogenName
                            + " { background-color : " + colorStr+ "; "
                            + "position : absolute; "
                            + "z-index : 2; "
                            + "} ";
        document.getElementById("autogenerated_css_classes").innerHTML = style.innerHTML;
        classDict[autogenName] = true;
    }
    return "autogenerated_class_" + colorStr;
}

var editor = ace.edit("editor");
editor.$blockScrolling = Infinity;
editor.setTheme("ace/theme/chrome");
editor.setFontSize(14);
editor.getSession().setMode("ace/mode/little");
editor.getSession().getDocument().on("change", maybeSendUpdate);
editor.getSession().selection.on("changeCursor", maybeSendUpdate);
editor.getSession().selection.on("changeSelection", maybeSendUpdate);

//Set the default scratch text to display before the first load
var defaultScratch =
" \n" +
"; Write a little program below.\n" +
"; Or choose an example from the list.\n" +
";\n" +
"; Changes to this *Scratch* example will be saved and\n" +
"; restored when navigating to and from other examples.\n" +
"; For the remaining named examples, changes will be\n" +
"; discarded when choosing a different example.\n" +
"\n" +
"(def reddiv \n" +
"  (div \n" +
"    [ (style \n" +
"        [ [ 'width' '100px' ]\n" +
"          [ 'height' '100px' ] \n" +
"          [ 'background-color' 'red' ]\n" +
"        ] )\n" +
"    ] \n" +
"    [] ) )\n" +
"(basicDoc [['bgcolor' 'lightblue']] [reddiv])"
editor.setValue(defaultScratch);
editor.moveCursorTo(0,0);

var updateWasFromElm = false;
var markers = [];

runtime.ports.aceInTheHole.subscribe(function(codeBoxInfo) {
    //Set our flag so that our event handlers don't update on any updates from
    // Elm
    updateWasFromElm = true;
    //Resize the editor window if the div size has changed
    editor.resize();
    //Set the value of the code editor with what we got from Elm
    editor.getSession().setValue(codeBoxInfo.code, 0);
    //Set the cursor position to what we got from Elm
    editor.moveCursorTo(codeBoxInfo.cursorPos.row, codeBoxInfo.cursorPos.column);
    //Set the selections appropriately
    //Note that we need to turn the Elm Ranges into Ace Range Objects
    editor.selection.clearSelection();

    //We need to treat the first one differently, so we must iterate
    //This is undocumented outside of the tests, see:
    // https://github.com/ajaxorg/ace/blob/0a3b002e285a41a4884ce42f94d2f68673e43b30/lib/ace/multi_select_test.js#L168
    //For the special namespacing, see:
    // http://stackoverflow.com/questions/10452869/when-i-try-to-create-a-range-object-in-ace-js-an-illegal-constructor-error-is
    var numRanges = codeBoxInfo.selections.length;
    for (var i = 0; i < numRanges; i++) {
        elmRange = codeBoxInfo.selections[i];
        var aceRange = new Range(elmRange.start.row,
                                 elmRange.start.column,
                                 elmRange.end.row,
                                 elmRange.end.column);
        if (i === 0) {
            //We only allow backwards selections if there is just one selection
            //We deduce if it's backwards by comparing the cursor position to
            // the end of the selection (which always orients itself such that
            // it's > the start in the process of constucting the Range)
            //Note that we use compareEnd here because the compare functions are
            // a little wonky - compareStart returns -1, for instance, if the
            // cursor is at the start.
            if (numRanges === 1) {
                if (aceRange.compareEnd(codeBoxInfo.cursorPos.row,
                                        codeBoxInfo.cursorPos.column) === 1) {
                    var backwards = false;
                } else {
                    var backwards = true;
                }
                editor.selection.setSelectionRange(aceRange, backwards);
            } else {
                editor.selection.fromOrientedRange(aceRange);
            }
        } else {
            editor.selection.addRange(aceRange, false);
        }
    }

    //Add the special syntax highlighting for changes and such
    //These are 'markers', see:
    //http://ace.c9.io/#nav=api&api=edit_session
    //ctl+f addMarker
    for (mi in markers) {
        editor.getSession().removeMarker(markers[mi]);
    }
    markers = [];
    for (hi in codeBoxInfo.highlights) {
        hiRange = codeBoxInfo.highlights[hi].range;
        var aceRange = new Range(hiRange.start.row - 1, //Indexing from 1 in Elm?
                                 hiRange.start.column - 1,
                                 hiRange.end.row - 1,
                                 hiRange.end.column - 1);
        var hiClass = makeCSSClass(codeBoxInfo.highlights[hi].color);
        var mid = editor.getSession().addMarker(aceRange,hiClass,"text", false);
        editor.resize();
        markers.push(mid);
    }
    editor.updateSelectionMarkers();

    //If the div rerendered (kept track of with a special attribute) then we
    // should copy the editor back into it
    var editorDiv = document.getElementById("editor");
    if (editorDiv.getAttribute("rendered") !== "true") {
      editorDiv.parentNode.replaceChild(editor.container, editorDiv);
      editorDiv.setAttribute("rendered","true");
    }
    
    //Set the contents to the correct manipulable state
    if (!codeBoxInfo.manipulable) {
        editor.container.style.zIndex = "0";
        editor.container.style.pointerEvents = "auto";
        editor.setReadOnly(true);
    } else {
        editor.container.style.zIndex = "1";
        editor.container.style.pointerEvents = "auto";
        editor.setReadOnly(false);
    }

    //If we should bounce an update back (force a rerender) then do so
    if (codeBoxInfo.bounce) {
        runtime.ports.theTurn.send(
            { evt : "Rerender"
            , strArg : ""
            , cursorArg : editor.getCursorPosition()
            , selectionArg : []
            }
        );
    }
    
    //Set our flag back to enable the event handlers again
    updateWasFromElm = false;
});

function maybeSendUpdate(e) {
    if (!updateWasFromElm) {
      runtime.ports.theTurn.send(
        { evt : "AceCodeUpdate"
        , strArg : editor.getSession().getDocument().getValue()
        , cursorArg : editor.getCursorPosition()
        , selectionArg : editor.selection.getAllRanges()
        }
      );
    }
}
