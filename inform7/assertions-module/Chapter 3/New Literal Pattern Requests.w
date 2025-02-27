[LPRequests::] New Literal Pattern Requests.

Special sentences creating new notations for literal values.

@ The ability to create new ways to write literal values is one of the best
features of Inform, but it is complex to parse, and has around 30 problem
messages associated with it. The |:literals| set of test cases may be useful
when tweaking the code below.

The first point to note is that "X specifies Y" sentences have two different
uses, but that both are covered below. First, they create literal patterns,
and the syntax for that can be quite involved:

>> 1 tonne (in metric units, in tonnes, singular) specifies a mass scaled up by 1000.

Second, they can gives dimensional instructions about kinds:

>> A length times a length specifies an area.

This is a slightly unhappy ambiguity, but the potential for confusion is low.
Nobody who defines a literal pattern with the word "times" in can expect good
results anyway, given that "times" will usually be interpreted as
multiplication when Inform eventually parses such a literal.

@ We create new literal patterns during pass 1, which imposes two timing
constraints:

(a) The specification sentence must come after the sentence creating the
kind of value being specified; but
(b) It must come before any sentences using constants written in this
notation.

In practice both constraints seem to be accepted by users as reasonable,
and this causes no trouble.

=
int LPRequests::specifies_SMF(int task, parse_node *V, wording *NPs) {
	wording SW = (NPs)?(NPs[0]):EMPTY_WORDING;
	wording OW = (NPs)?(NPs[1]):EMPTY_WORDING;
	switch (task) {
		case ACCEPT_SMFT: /* "10'23 specifies a running time." */
			if (<np-alternative-list>(SW)) {
				parse_node *S = <<rp>>;
				if (<np-unparsed>(OW)) {
					parse_node *O = <<rp>>;
					V->next = S; V->next->next = O;
					return TRUE;
				}
			}
			break;
		case PASS_1_SMFT:
			LPRequests::new_list(V->next, V->next->next, NULL);
			break;
	}
	return FALSE;
}

@ The code in this section parses sentences which set up new literal patterns,
puts the (quite complicated) result into a //lp_specification// object, and
sends that to //values: Literal Patterns//.

@d SINGULAR_LPN 1
@d PLURAL_LPN 2
@d ABANDON_LPN 4 /* for error recovery only */

=
typedef struct lp_specification {
	struct wording notation_wording; /* the actual notation, e.g., "2 tonnes" */
	struct kind *kind_specified; /* what kind this sentence specifies */

	int scaled_dir; /* one of the |LP_SCALED_*| constants above */
	int scale_factor;
	double scale_factor_as_double;

	struct parse_node *equivalent_value;
	double equivalent_value_as_double;

	struct parse_node *offset_value;
	double offset_value_as_double;

	int uses_real_arithmetic;

	int notation_options; /* a bitmap of the |*_LPN| values */
	struct literal_pattern_name *notation_groups; /* "in metric units", and so on */

	struct parse_node *part_np_list;
} lp_specification;

lp_specification glps;

void LPRequests::initialise(lp_specification *lps) {
	lps->scaled_dir = LP_SCALED_UP;
	lps->scale_factor = 1;
	lps->scale_factor_as_double = 1.0;
	lps->equivalent_value_as_double = 0.0;
	lps->equivalent_value = NULL;
	lps->offset_value_as_double = 0.0;
	lps->offset_value = NULL;
	lps->uses_real_arithmetic = FALSE;
	lps->notation_options = 0;
	lps->notation_groups = NULL;
	lps->notation_wording = EMPTY_WORDING;
	lps->part_np_list = NULL;
}

@ One can define LPs with a list of alternatives, of which the first is the
"primary alternative" and said to be the "owner" of the rest. For instance:

>> 1 tonne (in metric units, in tonnes, singular) or 2 tonnes (in metric units,
in tonnes, plural) specifies a mass scale_factor up by 1000.

Here "1 tonne" is the primary alternative, and it owns "2 tonnes".

=
literal_pattern *LPRequests::new_list(parse_node *p,
	parse_node *q, literal_pattern *m) {
	if (Node::get_type(p) == AND_NT) {
		m = LPRequests::new_list(p->down, q, m);
		return LPRequests::new_list(p->down->next, q, m);
	}
	LPRequests::initialise(&glps);
	@<Parse the object noun phrase of the specifies sentence@>;
	@<Parse the subject noun phrase of the specifies sentence@>;
	return LiteralPatterns::new_literal_specification_inner(&glps, p, q, m);
}

@<Parse the subject noun phrase of the specifies sentence@> =
	<specifies-sentence-subject>(Node::get_text(p));
	glps.notation_wording = GET_RW(<specifies-sentence-subject>, 1);
	glps.notation_options = <<r>>;
	glps.notation_groups = <<rp>>;
	if (glps.notation_options & ABANDON_LPN) return m;

@ The following grammar is used to parse the new literal patterns defined
in a "specifies" sentence.

Formally, the subject noun phrase of a "specifies" sentence must be a list
of alternatives each of which matches the following:

=
<specifies-sentence-subject> ::=
	... ( {<lp-group-list>} ) |                      ==> { pass 1 }
	<k-kind-articled> times <k-kind-articled> |      ==> @<Store left and right kinds@>
	<s-type-expression> times <s-type-expression> |  ==> @<Issue PM_MultiplyingNonKOVs problem@>
	... ==> { 0, NULL }

<lp-group-list> ::=
	<lp-group> <lp-group-tail> |  ==> { R[1] | R[2], LPRequests::compose(RP[1], RP[2]) }
	<lp-group>                    ==> { pass 1 }

<lp-group-tail> ::=
	, and <lp-group-list> |  ==> { pass 1 }
	,/and <lp-group-list>    ==> { pass 1 }

<lp-group> ::=
	singular |         ==> { SINGULAR_LPN, NULL }
	plural |           ==> { PLURAL_LPN, NULL }
	<lp-group-name> |  ==> { 0, LiteralPatterns::new_lpn(EMPTY_WORDING, RP[1]) }
	in ...... |        ==> { 0, LiteralPatterns::new_lpn(W, NULL) }
	......             ==> @<Issue PM_BadLPNameOption problem@>

@<Store left and right kinds@> =
	Kinds::Dimensions::dim_set_multiplication(RP[1], RP[2], glps.kind_specified);
	==> { ABANDON_LPN, - };

@<Issue PM_MultiplyingNonKOVs problem@> =
	if (preform_lookahead_mode == FALSE)
		StandardProblems::sentence_problem(Task::syntax_tree(), _p_(PM_MultiplyingNonKOVs),
			"only kinds of value can be multiplied here",
			"and only in a sentence like 'A length times a length specifies an area.'");
	==> { ABANDON_LPN, NULL }

@<Issue PM_BadLPNameOption problem@> =
	if (preform_lookahead_mode == FALSE) {
		Problems::quote_source(1, current_sentence);
		Problems::quote_wording(2, W);
		StandardProblems::handmade_problem(Task::syntax_tree(), _p_(PM_BadLPNameOption));
		Problems::issue_problem_segment(
			"In the specification %1, I was expecting that '%2' would be an optional "
			"note about one of the notations: it should have been one of 'singular', "
			"'plural' or 'in ...'.");
		Problems::issue_problem_end();
	}
	==> { ABANDON_LPN, NULL }

@<Parse the object noun phrase of the specifies sentence@> =
	glps.offset_value = NULL;
	<specifies-sentence-object>(Node::get_text(q));
	switch (<<r>>) {
		case PARTS_LPC: glps.part_np_list = <<rp>>; break;
		case SCALING_LPC: break;
	}
	if (glps.kind_specified == NULL) return m;

@ The object noun phrase of a "specifies" sentence is required to match
the following grammar. Note that the tails are mutually exclusive; you
can't set both scaling and an equivalent, for instance.

=
<specifies-sentence-object> ::=
	<kind-specified> <lp-specification-tail> |     ==> { pass 2 }
	<kind-specified>                               ==> { 0, NULL }

<kind-specified> ::=
	<k-kind-articled> |                            ==> { 0, NULL }; glps.kind_specified = RP[1];
	...                                            ==> @<Issue PM_LPNotKOV problem@>

<lp-specification-tail> ::=
	with parts <lp-part-list> |                    ==> { PARTS_LPC, RP[1] }
	<scaling-instruction> |                        ==> { SCALING_LPC, - }
	<scaling-instruction> offset by <s-literal> |  ==> @<Scaling together with offset@>
	offset by <s-literal> |                        ==> @<Offset alone@>
	equivalent to <s-literal>                      ==> @<Equivalency@>

<scaling-instruction> ::=
	scaled up by <scaling-amount> |    ==> { SCALING_LPC, - }; glps.scaled_dir = LP_SCALED_UP
	scaled down by <scaling-amount> |  ==> { SCALING_LPC, - }; glps.scaled_dir = LP_SCALED_DOWN
	scaled at <scaling-amount>         ==> { SCALING_LPC, - }; glps.scaled_dir = LP_SCALED_AT

<scaling-amount> ::=
	<cardinal-number> |      ==> @<Accept an integer scale factor@>
	<s-literal-real-number>  ==> @<Accept a real scale factor@>

@<Scaling together with offset@> =
	glps.offset_value_as_double = LiteralPatterns::get_latest_real();
	glps.offset_value = RP[2];
	==> { SCALING_LPC, - }; 

@<Offset alone@> =
	glps.offset_value_as_double = LiteralPatterns::get_latest_real();
	glps.offset_value = RP[1];
	==> { OFFSET_LPC, - };

@<Equivalency@> =
	glps.equivalent_value_as_double = LiteralPatterns::get_latest_real();
	glps.equivalent_value = RP[1];
	==> { EQUIVALENT_LPC, - };

@<Accept an integer scale factor@> =
	glps.scale_factor = R[1];
	glps.scale_factor_as_double = (double) R[1];
	==> { -, - };

@<Accept a real scale factor@> =
	glps.scale_factor = 1;
	glps.scale_factor_as_double = LiteralPatterns::get_latest_real();
	glps.uses_real_arithmetic = TRUE;
	==> { -, - };

@<Issue PM_LPNotKOV problem@> =
	if (preform_lookahead_mode == FALSE)
		StandardProblems::sentence_problem(Task::syntax_tree(), _p_(PM_LPNotKOV),
			"you can only specify ways to write kinds of value",
			"as created with sentences like 'A weight is a kind of value.'");

@ Of the optional tails, the only tricky one is the part list, which has the
following rather extensive grammar. This handles text like:

>> dollars and cents (optional, preamble optional)

The text is a list of part-names, each of which can optionally be followed
by a bracketed list of up to three options in any order.

=
<lp-part-list> ::=
	<lp-part> , and <lp-part-list> |               ==> { 0, Node::compose(RP[1], RP[2]) }
	<lp-part> , <lp-part-list> |                   ==> { 0, Node::compose(RP[1], RP[2]) }
	<lp-part> and <lp-part-list> |                 ==> { 0, Node::compose(RP[1], RP[2]) }
	<lp-part>                                      ==> { 0, RP[1] }

<lp-part> ::=
	<np-unparsed-bal> ( <lp-part-option-list> ) |  ==> { 0, LPRequests::mark(RP[1], R[2]) }
	<np-unparsed-bal>                              ==> { 0, RP[1] }

<lp-part-option-list> ::=
	<lp-part-option> <lp-part-option-tail> |       ==> { R[1] | R[2], - }
	<lp-part-option>                               ==> { pass 1 }

<lp-part-option-tail> ::=
	, and <lp-part-option-list> |                  ==> { pass 1 }
	,/and <lp-part-option-list>                    ==> { pass 1 }

<lp-part-option> ::=
	optional |                                     ==> { OPTIONAL_LSO, - }
	preamble optional |                            ==> { PREAMBLE_OPTIONAL_LSO, - }
	without leading zeros |                        ==> { WITHOUT_LEADING_ZEROS_LSO, - }
	......                                         ==> @<Issue PM_BadLPPartOption problem@>

@<Issue PM_BadLPPartOption problem@> =
	if (preform_lookahead_mode == FALSE) {
		Problems::quote_source(1, current_sentence);
		Problems::quote_wording(2, W);
		StandardProblems::handmade_problem(Task::syntax_tree(), _p_(PM_BadLPPartOption));
		Problems::issue_problem_segment(
			"In the specification %1, I was expecting that '%2' would be an optional "
			"note about one of the parts: it should have been one of 'optional', "
			"'preamble optional' or 'without leading zeros'.");
		Problems::issue_problem_end();
	}
	==> { 0, - };

@ =
literal_pattern_name *LPRequests::compose(literal_pattern_name *A, literal_pattern_name *B) {
	if (A == NULL) return B;
	A->next_with_rp = B;
	return A;
}

@ Nodes used as "parts" of a notation are annotated with a bitmap of these:

@d OPTIONAL_LSO 1
@d PREAMBLE_OPTIONAL_LSO 2
@d WITHOUT_LEADING_ZEROS_LSO 4

=
parse_node *LPRequests::mark(parse_node *A, int N) {
	if (A) Annotations::write_int(A, lpe_options_ANNOT, N);
	return A;
}
