%	preprocessing.pl : different functions: lemmatisation, chunking, adding information from morphological analysis

%search for 'uncomment' to see comments about different output formats.

%:- open_null_stream(Null),set_prolog_IO(user_input,user_output,Null).

:- set_prolog_flag(encoding,utf8).
:- set_stream(user_input, encoding(utf8));true.
:- set_stream(user_output, encoding(utf8));true.
:- system:prompt(_, '').
:- use_module(library(lists)).

:- dynamic sentno/1, posno/1, w/6, w/4, lvl/4, completed/2, lemmatisation/1, morphology/1,sentdelim/1.

:- ensure_loaded('preprocessing_verbchunkmodule.pl').

:- assert(morphology(gertwol)).
:- assert(lemmatisation(gertwol)).
:- assert(sentdelim('$.')).

%reads from stdin, writes to stdout
start(GERTWOL) :- retractall(w(_,_,_,_,_,_)), retractall(w(_,_,_,_)), retractall(sentno(_)), retractall(posno(_)), retractall(completed(_,_)), retractall(lvl(_,_,_,_)),
		   consult(GERTWOL),
		   assert(sentno(1)),
		   assert(posno(1)),
		   readsentences.


%reads a line and calls addnumber/1 to identify the sentence and position number.
readsentences :- repeat,
				read(X),
				addnumber(X),
				X == end_of_file,
			    !.


%addnumber/1: at the end of a sentence, posno is reset to 1 and sentno incremented by one. otherwise, posno is incremented by one.

%end of sentence
addnumber(X) :- sentdelim(SentDelim),
            X = w(Word,SentDelim,_,_C),
			sentno(Sentence),
			posno(Pos),
            jointag(Word,SentDelim,Chunk),
			assert(w(Sentence, Pos, Word,SentDelim,[Chunk],[-,-])),
			retract(sentno(_)),
			NewSentence is Sentence + 1,
			assert(sentno(NewSentence)),
			retract(posno(_)),
			NewPos is 1,
			assert(posno(NewPos)),
		    dochunking(Sentence),
		    tagcorrection(Sentence),
		    printwords(Sentence),
		    retractall(w(Sentence,_,_,_,_,_)),
			!.

%new word within sentence.
addnumber(X) :-		X = w(Word,Tag,_,C),
			sentno(Sentence),
			posno(Pos),
			(lemmatisation(none) -> Lemma=Word, NewTag=Tag;getlemma(Word, Tag, Lemma,NewTag)),
			jointag(Lemma,NewTag,Chunk),
			assert(w(Sentence, Pos, Word,NewTag,[Chunk],C)),
			retract(posno(_)),
			NewPos is Pos + 1,
			assert(posno(NewPos)),
			!.

%end_of_file has to succeed.
addnumber(X) :- X == end_of_file, !.


printwords(Sentence) :-
            sentdelim(SentDelim),
			w(Sentence,StopPos,_,SentDelim,_,_),
			nl,
			between(1,StopPos,Pos),
			writedown(Sentence,Pos),
			fail.

printwords(_) :- !.

%cycles through all the words (this method makes sure that the print-out is in the right order) and calls writedown every time.
printwords :- sentdelim(SentDelim),
            sentno(SenNum),
			between(1,SenNum,Sentence),
			w(Sentence,StopPos,_,SentDelim,_,_),
			nl,
			between(1,StopPos,Pos),
			writedown(Sentence,Pos),
			fail.

printwords :- !.

%writedown(+SenNr,+PosNr,+OutStream)
writedown(Sentence,Pos) :-
			w(Sentence,Pos,Word,Tag,Chunk,MorphIn),
			(lemmatisation(none) -> Lemma=Word;getlemma(Word, Tag, Lemma,Tag)),
			(morphology(keep) -> MorphOut = MorphIn;buildmorphology(Word,Tag, MorphOut)), 
%Next line is commented for Progresde-compatible input. Uncommenting might be useful for debugging purposes
%                       Outline =.. [w,Sentence, Pos, Lemma,Tag,Chunk,MorphOut],
                        Outline =.. [w,Lemma,Tag,Chunk,MorphOut],
                        writeq(Outline),
                        write('.'),
                        nl,
                        !.


%cycles through all sentences and calls idstart/3.
dochunking  :- 	sentno(SenNum),
		between(1,SenNum,Sentence),
		retractall(completed(_,_)),
		retractall(lvl(_,_,_,_)),
		idstart(Sentence, 1,1),
		fail.

dochunking.


dochunking(Sentence) :- 		retractall(completed(_,_)),
		retractall(lvl(_,_,_,_)),
		idstart(Sentence, 1,1).


tagcorrection(Sentence) :- tagstart(Sentence, 1).


%Der Hamburgische Ministerpräsident; die Vereinten Nationen: treat first noun as adjective.
tagstart(Sentence,Pos) :- w(Sentence,Pos,Word,Tag,_,_), 
			  (Tag='NN';Tag='NE';Tag='FM'),
		          PosRight is Pos + 1,
			  w(Sentence,PosRight,_,'NN',_,_),
			  forcetag(Word,Tag,Lemma,'ADJA'), !,
			  jointag(Lemma,'ADJA',NewString),
			  retract(w(Sentence,Pos,Word,Tag,_,Morph)),
			  assert(w(Sentence,Pos,Word,'ADJA',[NewString],Morph)),
			  NewPos is Pos + 1,
			  tagstart(Sentence,NewPos).

%sentence finished
tagstart(Sentence,Pos) :- sentdelim(SentDelim),
                        w(Sentence,Pos,_,SentDelim,_,_), !.

%nothing found - repeat search with next position.
tagstart(Sentence,Pos) :- sentdelim(SentDelim),
              w(Sentence,_,_,SentDelim,_,_),
			  NewPos is Pos + 1,
			  tagstart(Sentence,NewPos).

%catchall - just in case.
tagstart(_,_) :- !.

%==============================================================================
%morphology and lemmatising


buildmorphology(Word,_, [Word|[_]]) :- morphology(none), !.

%exception: deren and dessen as attributive pronouns don't need to agree with their heads.
buildmorphology(dessen,'PRELAT',[dessen,_]) :-  !.
buildmorphology(deren,'PRELAT',[deren,_]) :- !.
buildmorphology(dessen,'PDAT',[dessen,_]) :-  !.
buildmorphology(deren,'PDAT',[deren,_]) :- !.

%try spelling variations if word doesn't exist in Gertwol.
buildmorphology(Word,Tag,[Word|ListOut]) :- (\+ (gertwol(Word,Lemma,_,_, _), \+ Lemma = '<unknown>')->(spellingvariation(Word,NewWord), \+ NewWord = Word,buildmorphology(NewWord,Tag,[_|ListOut]));fail).

%exception: nouns may be substantivized adjectives.
buildmorphology(Word,'NN',[Word|ListOut]) :- findall(Morph,gertwol(Word,_,'NN',Morph,_),ListTemp),
				      findall([Gender,Case,Number,_],gertwol(Word,_,'ADJA',[_,Gender,Case,Number,'Sw'],_),ListTemp2),
				      append(ListTemp,ListTemp2,ListTemp3),
				      (is_uninstantiated(ListTemp3) -> ListOut = [_] ; translatemorphs(ListTemp3,'NN', ListTemp4), sort(ListTemp4,ListTemp5), my_remove_duplicates(ListTemp5,ListOut)), !.

%exception: viele/wenige are PIS/PIDAT in TreeTagger, but ADJA in Gertwol
buildmorphology(Word,Tag,[Word|ListOut]) :- (Tag = 'PIS';Tag='PIDAT'),
				      \+ gertwol(Word,_,Tag,_,_),
				      findall([Gender,Case,Number],gertwol(Word,_,'ADJA',[_,Gender,Case,Number,_],_),ListTemp),
				      (is_uninstantiated(ListTemp) -> ListOut = [_] ; sort(ListTemp,ListOut)), !.


%exception: Wegen dem Dativ gibt es immer weniger Präpositionen, die nur mit Genitiv benutzt werden
buildmorphology(Word,'APPR',[Word|ListOut2]) :- findall(Morph,gertwol(Word,_,'APPR',Morph,_),ListTemp),
                                        (is_uninstantiated(ListTemp) -> ListOut = [_] ; translatemorphs(ListTemp,'APPR', ListOut)), (ListOut = [['Gen']]->append(ListOut,[['Dat']],ListOut2);ListOut2=ListOut), !.


%adjectives; include information on whether it's a participial one or not:
buildmorphology(Word,'ADJA',[Word|ListOut]) :- findall([Deg,Gender,Case,Number,Class,Original],gertwol(Word,_,'ADJA',[Deg,Gender,Case,Number,Class],Original),ListTemp),
                    (is_uninstantiated(ListTemp) -> ListOut = [_] ; translatemorphs(ListTemp,'ADJA', ListTemp2), sort(ListTemp2,ListTemp3), my_remove_duplicates(ListTemp3,ListOut)), !.

buildmorphology(Word,'ADJD',[Word|ListOut]) :- findall([Degree,Original],gertwol(Word,_,'ADJD',[Degree],Original),ListTemp),
                    (is_uninstantiated(ListTemp) -> ListOut = [_] ; translatemorphs(ListTemp,'ADJD', ListTemp2), sort(ListTemp2,ListTemp3), my_remove_duplicates(ListTemp3,ListOut)), !.

% general case:
buildmorphology(Word,Tag,[Word|ListOut]) :- findall(Morph,gertwol(Word,_,Tag,Morph,_),ListTemp),
                                        (is_uninstantiated(ListTemp) -> ListOut = [_] ; translatemorphs(ListTemp,Tag, ListTemp2), sort(ListTemp2,ListTemp3), my_remove_duplicates(ListTemp3,ListOut)), !.

translatemorphs([],_,[]) :- !. %break condition.


% translatemorphs([In|Ins],'ADJAtoNN',[Out|Outs]) :- translatelist('ADJAtoNN',In,Out), !,
% 					    translatemorphs(Ins,'ADJAtoNN',Outs). %catchall.

translatemorphs([In|Ins],'NN',[Out|Outs]) :- translatelist('NN',In,Out), !,
                                           translatemorphs(Ins,'NN',Outs). %catchall.

translatemorphs([In|Ins],Tag,[Out|Outs]) :- translatelist(general,In,Out), !,
					    translatemorphs(Ins,Tag,Outs). %catchall.


translatelist(general,[],[]) :- !. %break condition

%when converting from adjective morphology to noun morphology, throw first item away.
% translatelist('ADJAtoNN',[_|Ins],[Outs]) :-  !,
% 						translatelist(general,Ins,Outs).

%throw last member of noun morphology away.
translatelist('NN',[_],[]) :- !.

translatelist('NN',[In|Ins],[Out|Outs]) :-  !,         morphmapping(In,Out), !,
                                               translatelist('NN',Ins,Outs).

translatelist(general,[In|Ins],[Out|Outs]) :- morphmapping(In,Out), !,
						translatelist(general,Ins,Outs).

%if all elements in the list are variable, output should be variable '_'
is_uninstantiated([]) :- !.

is_uninstantiated([Elem]) :- var(Elem), !.

is_uninstantiated([List]) :- is_uninstantiated(List).

is_uninstantiated([First|Rest]) :- var(First),
			is_uninstantiated(Rest).

morphmapping(*,_).

morphmapping(X,X). %catchall


%override some TreeTagger analyses.
% getlemma(was,_Tag,was,'PWS') :- !.

%noch (in 'weder x noch y') is often mistagged as adverb
getlemma(noch,_,noch,'KON') :- w(_,_,Word,_,_,_),member(Word,[weder,'Weder']), !.

% Sometimes, TreeTagger has problems with Ein.
getlemma('Ein',_,ein,'ART') :- !.
getlemma('Einen',_,ein,'ART') :- !.
getlemma('Einem',_,ein,'ART') :- !.

%normal case: treetagger and gertwol agree
getlemma(Word,Tag,Lemma,Tag) :- gertwol(Word,Lemma,Tag,_Analysis, _), \+ Lemma = '<unknown>', !.

%exception: if TreeTagger says 'NN', and Gertwol only knows word as 'NE', use 'NE'
getlemma(Word,'NN',Lemma,'NE') :- gertwol(Word,Lemma,'NE',_Analysis, _), \+ Lemma = '<unknown>', !.

%exception: Sometimes, sentence-initial adjectives are mistagged as nouns. (but dual-names like Kühlmann-Stumm may be mistagged as adjectives by Gertwol, so make sure it isn't one)
getlemma(Word,'NN',Lemma,'ADJD') :- gertwol(Word,Lemma,'ADJD',_Analysis, _), \+ Lemma = '<unknown>', \+ (name(Word,WordChars), member(45,WordChars)), !.
getlemma(Word,'NE',Lemma,'ADJD') :- gertwol(Word,Lemma,'ADJD',_Analysis, _), \+ Lemma = '<unknown>', \+ (name(Word,WordChars), member(45,WordChars)), !.


% Gertwol doesn't distinguish between modal/auxiliary/full verbs
getlemma(Word,'VAFIN',Lemma,'VAFIN') :- morphology(gertwol), gertwol(Word,Lemma,'VVFIN',_Analysis,_), \+ Lemma = '<unknown>', !.
getlemma(Word,'VAINF',Lemma,'VAINF') :- morphology(gertwol), gertwol(Word,Lemma,'VVINF',_Analysis,_), \+ Lemma = '<unknown>', !.
getlemma(Word,'VAPP',Lemma,'VAPP') :- morphology(gertwol), gertwol(Word,Lemma,'VVPP',_Analysis,_), \+ Lemma = '<unknown>', !.
getlemma(Word,'VMFIN',Lemma,'VMFIN') :- morphology(gertwol), gertwol(Word,Lemma,'VVFIN',_Analysis,_), \+ Lemma = '<unknown>', !.
getlemma(Word,'VMINF',Lemma,'VMINF') :- morphology(gertwol), gertwol(Word,Lemma,'VVINF',_Analysis,_), \+ Lemma = '<unknown>', !.
getlemma(Word,'VMPP',Lemma,'VMPP') :- morphology(gertwol), gertwol(Word,Lemma,'VVPP',_Analysis,_), \+ Lemma = '<unknown>', !.


%next case: POS tag from Gertwol overrides TreeTagger. Free choice
% getlemma(Word,Tag,Lemma,NewTag) :- gertwol(Word,Lemma,NewTag,_Analysis, _), \+ Lemma = '<unknown>',
% 				      \+ member(Tag,['FM','PTKNEG','PWAV','ITJ']), %in case of conflict, we sometimes want to prefer TreeTagger tags.
% 				      write('%word/tag combination not found in gertwol:'), write(Word), write(' '),write(Tag),write(' - using '), write(NewTag), write(' instead.\n'),
% 				      !.

%try spelling variations
getlemma(Word,InTag,Lemma,OutTag) :- spellingvariation(Word,NewWord), \+ NewWord = Word, !,
      getlemma(NewWord,InTag,Lemma,OutTag).



%catchall if all else fails.
getlemma(Word,Tag,Word,Tag) :- findall(Tag2, (gertwol(Word,Lemma,Tag2,_, _),\+ Lemma = '<unknown>'), List),
			    length(List,Len),
			    sort(List,AltList),
			    (Len > 0 -> (write('%word/tag combination not found in gertwol:'), write(Word), write(' '),write(Tag),write(' - alternatives proposed by Gertwol: '), write(AltList), write('\n'));true),
			    !. 


%try spelling variations until we find one that Gertwol recognizes
spellingvariation(Word,Word) :- gertwol(Word,Lemma,_,_, _), \+ Lemma = '<unknown>', !.

spellingvariation(Word,OutWord) :- name(Word,Chars), 
                               (Chars=[65,101|Rest]->NewChars=[196|Rest];
                                  (Chars=[79,101|Rest]->NewChars=[214|Rest];
                                    (Chars=[85,101|Rest]->NewChars=[220|Rest];
                                        (append(Before,[115,115|After],Chars), 
                                         append(Before,[223],Start),
                                         append(Start,After,NewChars))))),
                               name(NewWord,NewChars),
                               spellingvariation(NewWord,OutWord).


%standard sort only removes duplicates if no variables are involved.
%we want [[_,'Akk'],[_,'Akk']] to be reduced to [[_,'Akk']]
my_remove_duplicates(L,Unique) :- duplicate_check(L,[],Unique).

duplicate_check([],Acc,Acc) :- !.
duplicate_check([H|T],Acc,Unique) :- \+ member(H,Acc), !, duplicate_check(T,[H|Acc],Unique).
duplicate_check([_|T],Acc,Unique) :- duplicate_check(T,Acc,Unique).

%==============================================================================


%sample call
%:- nl,write('copy & paste:'), nl, write('start(\'tueba_input.pl\', \'tueba_vchunk.pl\').'), nl, write(' ').
