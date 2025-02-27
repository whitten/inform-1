[Assertions::PropertyKnowledge::] Property Knowledge.

This section draws inferences from assertions which seem to be
about the properties of things, independent of their location.

@h Asserting global variable values.

=
void Assertions::PropertyKnowledge::initialise_global_variable(nonlocal_variable *q, parse_node *val) {
	if (q == NULL) internal_error("tried to initialise null variable");
	VariableSubjects::typecheck_initial_value(q, val, FALSE);

	parse_node *var = Lvalues::new_actual_NONLOCAL_VARIABLE(q);
	pcalc_prop *prop = Propositions::Abstract::to_set_relation(R_equality, NULL, var, NULL, val);
	Assert::true(prop, prevailing_mood);
}

@h Asserting properties, three different ways.
In these three alternative functions, we can assert that a given owner -- specified
either as an object, a value or a subtree -- should have

(a) a given single property equal to a value given as a subtree,
(b) a given single property equal to an explicit value, or
(c) a whole list of properties and their values.

=
void Assertions::PropertyKnowledge::assert_property_value_from_property_subtree_infs(property *prn,
	inference_subject *owner, parse_node *val_subtree) {
	pcalc_prop *prop = Propositions::Abstract::from_property_subtree(prn, val_subtree);
	if (owner == NULL) @<Issue a problem for an unrecognised property owner@>;
	Assert::true_about(prop, owner, prevailing_mood);
}

void Assertions::PropertyKnowledge::assert_property_list(parse_node *owner_subtree,
	parse_node *list_subtree) {
	@<Check that the owner subtree isn't dangerously elaborate@>;
	inference_subject *owner = Node::get_subject(owner_subtree);
	if (owner == NULL) {
		parse_node *owner_spec = NULL;
		if (<s-type-expression>(Node::get_text(owner_subtree)))
			owner_spec = <<rp>>;
		if ((Specifications::is_description(owner_spec)) &&
			(Descriptions::is_qualified(owner_spec) == FALSE)) {
			kind *K = Specifications::to_kind(owner_spec);
			if (K) owner = KindSubjects::from_kind(K);
		}
	}
	if (owner == NULL) {
		LOG("OS is: $T\n", owner_subtree);
		@<Issue a problem for an unrecognised property owner@>;
	}
	kind *kind_clue = NULL;
	@<Work out the clue kind@>;
	pcalc_prop *prop = Propositions::Abstract::from_property_list(list_subtree, kind_clue);
	Assert::true_about(prop, owner, prevailing_mood);
}

@ We pass the "clue kind" to obtain a proposition which includes an atom
setting the kind of the free variable -- not because we need to assert this,
although it does no harm to, but because this enables the proposition
asserter to know the kind of the free variable, which in turn affects the
interpretation placed on adjectives which have different meanings in different
domains. (Within "object", we needn't narrow down, though, because adjectives
are typechecked at run-time rather than compile-time in that domain.)

@<Work out the clue kind@> =
	if (owner) {
		kind_clue = KindSubjects::to_kind(owner);
		if (kind_clue == NULL)
			kind_clue = KindSubjects::to_kind(InferenceSubjects::narrowest_broader_subject(owner));
		if ((InferenceSubjects::is_an_object(owner)) ||
			(InferenceSubjects::is_a_kind_of_object(owner)))
			kind_clue = K_object;
	}

@<Check that the owner subtree isn't dangerously elaborate@> =
	parse_node *owner_spec = Node::get_evaluation(owner_subtree);
	if (Specifications::is_description(owner_spec)) {
		if ((Propositions::contains_binary_predicate(Specifications::to_proposition(owner_spec))) ||
			(Descriptions::number_of_adjectives_applied_to(owner_spec) > 0) ||
			(Propositions::contains_adjective(Specifications::to_proposition(owner_spec)))) {
			Problems::quote_source(1, current_sentence);
			Problems::quote_spec(2, owner_spec);
			StandardProblems::handmade_problem(Task::syntax_tree(), _p_(PM_RelationAPL));
			Problems::issue_problem_segment(
				"The sentence %1 looked to me as if it might be trying to assign certain "
				"properties to something described in a way (%2) which involved a clause "
				"which can't be properly determined until the game is running, so that at "
				"this point it's impossible to act upon.");
			Problems::issue_problem_end();
			return;
		}
	}

@<Issue a problem for an unrecognised property owner@> =
	Problems::quote_source(1, current_sentence);
	StandardProblems::handmade_problem(Task::syntax_tree(), _p_(PM_PropForBadKOV));
	Problems::issue_problem_segment(
		"The sentence %1 looked to me as if it might be trying to assign certain properties "
		"to something which is not allowed to have them.");
	Problems::issue_problem_end();
	return;

@ The following assumes that the subtree |py| describes a value which the
|prn| property of something will have; it issues problem messages if this
would be impossible, returning |NULL|, or else silently returns the value.
It's used both above and by the tree-conversion code in the predicate
calculus engine.

Here there's no need to perform any typechecking; all of that is done by
the proposition machinery. But we do look for empty lists, whose implied kind
can only be deduced from a wider context than that proposition describes.

=
parse_node *Assertions::PropertyKnowledge::property_value_from_property_subtree(property *prn, parse_node *py) {
	if (Properties::is_either_or(prn)) {
		if (py == NULL) @<Issue a problem, as this uses a bare adjective as if a value-property@>;
		@<Issue a problem, as this makes sense only for value properties@>;
	}
	@<Check that the subtree does indeed express a property value@>;

	parse_node *val = NonlocalVariables::substitute_constants(
		Node::get_evaluation(py));
	kind *property_kind = ValueProperties::kind(prn);

	@<Cast the empty list to whatever kind of list is expected@>;

	if ((Specifications::is_value(val)) && (Node::is(val, CONSTANT_NT) == FALSE))
		@<Issue a problem for a property value which isn't a constant@>;

	return val;
}

@<Cast the empty list to whatever kind of list is expected@> =
	kind *constant_kind = Specifications::to_kind(val);
	if ((Kinds::get_construct(constant_kind) == CON_list_of) &&
		(Kinds::eq(Kinds::unary_construction_material(constant_kind), K_nil)) &&
		(Lists::length_of_ll(Node::get_text(val)) == 0) &&
		(Kinds::get_construct(property_kind) == CON_list_of)) {
		Lists::set_kind_of_list_at(Node::get_text(val), property_kind);
		Node::set_kind_of_value(val, property_kind);
		constant_kind = property_kind;
	}

@<Issue a problem, as this uses a bare adjective as if a value-property@> =
	Problems::quote_source(1, current_sentence);
	Problems::quote_property(3, prn);
	StandardProblems::handmade_problem(Task::syntax_tree(), _p_(PM_HasBareAdjective));
	Problems::issue_problem_segment(
		"In %1 you write about the %3 property as if it were some kind of value "
		"or possession, but %3 is an either/or property - something is either "
		"%3 or not. (For example, it's incorrect to say 'The glass box has "
		"transparent'; the right way is just 'The glass box is transparent.')");
	Problems::issue_problem_end();
	return NULL;

@<Issue a problem, as this makes sense only for value properties@> =
	Problems::quote_source(1, current_sentence);
	Problems::quote_wording(2, Node::get_text(py));
	Problems::quote_property(3, prn);
	StandardProblems::handmade_problem(Task::syntax_tree(), _p_(BelievedImpossible));
	Problems::issue_problem_segment(
		"In %1 you give a value of the %3 property as '%2', but %3 is an either/or "
		"property - something is either %3 or not, so there is no value involved.");
	Problems::issue_problem_end();
	return NULL;

@<Check that the subtree does indeed express a property value@> =
	Refiner::nominalise_adjective(py);
	switch(Node::get_type(py)) {
		case PROPER_NOUN_NT:
			if ((Node::get_evaluation(py) == NULL) ||
				(Node::is(Node::get_evaluation(py), UNKNOWN_NT))) {
				Problems::quote_source(1, current_sentence);
				Problems::quote_wording(2, Node::get_text(py));
				Problems::quote_property(3, prn);
				StandardProblems::handmade_problem(Task::syntax_tree(), _p_(PM_PropertyValueUnknown));
				Problems::issue_problem_segment(
					"You wrote %1, but that seems to set a property %3 to the "
					"value '%2', which I don't recognise as meaning anything.");
				Problems::issue_problem_end();
				return NULL;
			}
			break; /* (this is fine -- there's a well-expressed value) */
		case COMMON_NOUN_NT:
			StandardProblems::sentence_problem(Task::syntax_tree(), _p_(PM_PropertyInstance),
				"this property value makes no sense to me",
				"since it looks as if it contains a relative clause. Sometimes this "
				"happens if a clause follows directly on, and I have misunderstood to "
				"what it belongs. For instance: 'The widget is a door with matching "
				"key a thing in the Ballroom' is read with 'a thing in the Ballroom' as "
				"the value of the 'matching key' property, not with 'in the Ballroom' "
				"applying to the door.");
			return NULL;
		case X_OF_Y_NT:
			StandardProblems::sentence_problem(Task::syntax_tree(), _p_(BelievedImpossible),
				"something grammatically odd has happened here",
				"possibly to do with the unexpected 'of' in what seems to be a list of "
				"property values?");
			return NULL;
		case WITH_NT:
			StandardProblems::sentence_problem(Task::syntax_tree(), _p_(PM_MisplacedFrom),
				"something grammatically odd has happened here",
				"possibly to do with the unexpected 'with' in what seems "
				"to be a list of property values? Maybe there is some punctuation missing.");
			return NULL;
		default:
			Problems::quote_source(1, current_sentence);
			Problems::quote_wording(2, Node::get_text(py));
			Problems::quote_property(3, prn);
			StandardProblems::handmade_problem(Task::syntax_tree(), _p_(PM_PeculiarPropertyValue));
			Problems::issue_problem_segment(
				"You wrote %1, but that seems to set a property %3 to the "
				"value '%2', which really doesn't make sense.");
			Problems::issue_problem_end();
			return NULL;
	}

@<Issue a problem for a property value which isn't a constant@> =
	Problems::quote_source(1, current_sentence);
	Problems::quote_wording(2, Node::get_text(py));
	Problems::quote_kind(3, property_kind);
	Problems::quote_property(4, prn);
	StandardProblems::handmade_problem(Task::syntax_tree(), _p_(PM_PropertyNonConstant));
	Problems::issue_problem_segment(
		"In %1 you give a value of the %4 property as '%2', "
		"and while this does make sense as %3, it is a value which "
		"exists and changes during play, and which doesn't make sense to "
		"use when setting up the initial state of things.");
	Problems::issue_problem_end();
	return NULL;
