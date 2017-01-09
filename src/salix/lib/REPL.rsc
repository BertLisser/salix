module salix::lib::REPL

import salix::lib::XTerm;
import salix::App;
import salix::Core;
import salix::HTML;

import util::Maybe;
import ParseTree;
import List;
import IO;
import String;


alias Model = tuple[
  str id,
  str prompt,
  list[str] history,
  int pointer,
  str currentLine,
  Msg(str) eval,
  list[str] completions,
  int cycle,
  list[str](str) complete,
  Maybe[str](str) highlight
];

WithCmd[Model] initRepl(str id, str prompt, Msg(str) eval, list[str](str) complete, Maybe[str](str) highlight) 
  = withCmd(<id, prompt, [], 0, "", eval, [], -1, complete, highlight>, write(noOp(), id, prompt)); 
  
data Msg
  = xtermData(str s)
  | noOp()
  | dummy(str s)  
  ;
  
  
WithCmd[Model] replaceLine(Model model, str newLine) 
  = withCmd(model[currentLine=newLine], writeLine(model, newLine));

Cmd writeLine(Model model, str newLine) {
  str zap = ( "\r" | it + " " | int _ <- [0..size(model.currentLine) + size(model.prompt)] );
  if (just(str highlighted) := model.highlight(newLine)) {
    newLine = highlighted;
  }
  return write(noOp(), model.id, "<zap>\r<model.prompt><newLine>");
}

WithCmd[Model] update(Msg msg, Model model) {
  Cmd cmd = none();
  
  switch (msg) {
    case xtermData(str s): {
      if (s != "\t") {
        model.cycle = -1;
      }
      if (s == "\r") {
        cmd = write(model.eval(model.currentLine), model.id, "\r\n<model.prompt>");
        model.history += [model.currentLine];
        model.pointer = size(model.history);
        model.currentLine = "";
      }
      else if (s == "\a7f") {
        cmd = write(noOp(), model.id, "\b");
      }
      else if (s == "\a1b[A") { // arrow up
        if (model.pointer > 0) {
          model.pointer -= 1;
          <model, cmd> = replaceLine(model, model.history[model.pointer]); 
        }
      }
      else if (s == "\a1b[B") { // arrow down
        if (model.pointer < size(model.history) - 1) {
	        model.pointer += 1;
	        <model, cmd> = replaceLine(model, model.history[model.pointer]);
        }
      }
      else if (s == "\t") {
        if (model.cycle == -1) {
          model.completions = model.complete(model.currentLine);
        }
        if (model.cycle < size(model.completions) - 1) {
          model.cycle += 1;
        }
        else {
          model.cycle = 0;
        }
        str comp = model.completions[model.cycle];
        <model, cmd> = replaceLine(model, model.completions[model.cycle]);
      }
      else if (/[a-zA-Z0-9_\ ]/ := s) {
        model.currentLine += s;
        if (just(str x) := model.highlight(s)) {
          s = x;
        }
        cmd = write(noOp(), model.id, s);
      }
      else {
        println("Unrecognized: <s>");
      }
    }
    case dummy(str s):
      println("Command: <s>");
  }
  
  return withCmd(model, cmd);
}  


void repl(Msg(Msg) f, Model m, str id, value vals...) {
   mapView(f, m, repl(id, vals));
}

void(Model) repl(str id, value vals...) {
  return void(Model m) {
     xterm(id, [onData(xtermData)] + vals); 
  };
}

list[str] dummyCompleter(str prefix) {
  list[str] xs = ["aap", "nooit", "noot", "mies", "muis"];
  return [ x | x <- xs, startsWith(x, prefix) ] + [prefix];
}


Maybe[str] dummyHighlighter(str x) {
  bool isVowel(str c) = c in {"a", "u", "i", "e", "o"};
  return  just(( "" | it + (isVowel(c) ? "\u001B[0;31m<c>\u001B[0m" : c) | int i <- chars(x), str c := stringChar(i) ));
} 
 

WithCmd[Model] init() = initRepl("x", "$ ", dummy, dummyCompleter, dummyHighlighter);

App[Model] replApp()
  = app(init, sampleView, update, |http://localhost:5001|, |project://salix/src|
       parser = parseMsg);

Msg identity(Msg m) = m;

void sampleView(Model m) {
  div(() {
    h4("Command line");
    repl(identity, m, "x", cursorBlink(true), cols(25), rows(10));
  });       
}



map[str, str] cat2ansi = (
  "Type": "",
  "Identifier": "",
  "Variable": "",
  "Constant": "",
  "Comment": "\u001B[3m", // italics
  "Todo": "",
  "MetaAmbiguity": "\u001B[0;31m", // red
  "MetaVariable": "",
  "MetaKeyword": "\u001B[1;35m", // bold purple
  "StringLiteral": ""
);


str ansiHighlight(Tree t, map[str,str] cats = cat2ansi, int tabsize = 2) = highlightRec(t, cats, tabsize);

str highlightRec(Tree t,  map[str,str] cats, int tabsize) {

  str reset = "\u001B[0m";
  
  str highlightArgs(list[Tree] args) 
    = ("" | it + highlightRec(a, cats, tabsize) | Tree a <- args );
  
  switch (t) {
    
    case appl(prod(lit(/^<s:[a-zA-Z_0-9]+>$/), _, _), list[Tree] args): {
      return "<cats["MetaKeyword"]><s><reset>";
    }

    case appl(prod(Symbol d, list[Symbol] ss, set[Attr] as), list[Tree] args): {
      if (\tag("category"(str cat)) <- as) {
        // categories can't be nested
        return "<cats[cat]><s><reset>";
      }
      return highlightArgs(args);
    }
    
    case appl(_, list[Tree] args):
      return highlightArgs(args);
    
    case char(int c): { 
      str s = stringChar(c);
      return  s == "\t" ? ("" | it + " " | _ <- [0..tabSize]) : s;
    }
    
    case amb(set[Tree] alts): {
      if (Tree a <- alts) {
        return highlightRec(a, cats);
      }
    }

  }
  
  return "";
    
} 