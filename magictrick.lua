MagicTrick = {}

function MTemp(source_a, target_a, card)
	local _t = source_a.cards[card]
	source_a:remove_card(_t)
	target_a:emplace(_t)
end

function MTP()
	MTemp(G.jokers, G.hand, 1)
end
 
function MPT()
	MTemp(G.hand, G.jokers, 1)
end

local no_rank_hook = SMODS.has_no_rank
SMODS.has_no_rank = function(card)
	if card.playing_card then
		return no_rank_hook(card)
	else
		return true --todo: expand
	end
end

local no_suit_hook = SMODS.has_no_suit
SMODS.has_no_suit = function(card)
	if card.playing_card then
		return no_suit_hook(card)
	else
		return true --todo: expand
	end
end

local always_scores_hook = SMODS.always_scores
SMODS.always_scores = function(card)
	if card.playing_card then
		return always_scores_hook(card)
	else
		return true --todo: expand
	end
end

-- SMODS.calculate_context except with a playing card/joker neutral eval function
function MagicTrick.calculate_context(context, return_table)
	context.cardarea = G.jokers
    context.main_eval = true
    for _, area in ipairs(SMODS.get_card_areas('jokers')) do
		for _, _card in ipairs(area.cards) do
			MagicTrick.eval_card(_card, context, return_table)
		end
	end
	context.main_eval = nil
	if context.scoring_hand then
		context.cardarea = G.play
		for i=1, #context.scoring_hand do
			MagicTrick.eval_card(context.scoring_hand[i], context, return_table)
		end
		if SMODS.optional_features.cardareas.unscored then
			context.cardarea = 'unscored'
			local unscored_cards = {}
			for _, played_card in pairs(G.play.cards) do
				if not SMODS.in_scoring(played_card, context.scoring_hand) then unscored_cards[#unscored_cards + 1] = played_card end
			end
			for i=1, #unscored_cards do
				MagicTrick.eval_card(unscored_cards[i], context, return_table)
			end
		end
	end
    context.cardarea = G.hand
	for i=1, #G.hand.cards do
		MagicTrick.eval_card(G.hand.cards[i], context, return_table)
	end
	if SMODS.optional_features.cardareas.deck then
	context.cardarea = G.deck
		for i=1, #G.deck.cards do
			MagicTrick.eval_card(G.deck.cards[i], context, return_table)
		end
	end
	if SMODS.optional_features.cardareas.discard then
		context.cardarea = G.discard
		for i=1, #G.discard.cards do
			MagicTrick.eval_card(G.discard.cards[i], context, return_table)
		end
	end
	local effect = G.GAME.selected_back:trigger_effect(context)
    if effect then SMODS.calculate_effect(effect, G.deck.cards[1] or G.deck) end
end

function MagicTrick.eval_playing_card(card, context, return_table)
	--calculate the played card effects
	if return_table then 
		return_table[#return_table+1] = eval_card(card, context)
		SMODS.calculate_quantum_enhancements(card, return_table, context)
	else
		local effects = {eval_card(card, context)}
		SMODS.calculate_quantum_enhancements(card, effects, context)
		SMODS.trigger_effects(effects, card)
	end
end

function MagicTrick.eval_joker(card, context, return_table)
	local eval, post = eval_card(card, context)
	local effects = {eval}
	for _,v in ipairs(post) do effects[#effects+1] = v end

	if context.other_joker then
		for k, v in pairs(effects[1]) do
			v.other_card = card
		end
	end
	if effects[1].retriggers then
		context.retrigger_joker = true
		for rt = 1, #effects[1].retriggers do
			context.retrigger_joker = effects[1].retriggers[rt].retrigger_card
			local rt_eval, rt_post = eval_card(card, context)
			table.insert(effects, {effects[1].retriggers[rt]})
			table.insert(effects, rt_eval)
			for _,v in ipairs(rt_post) do effects[#effects+1] = v end
		end
		context.retrigger_joker = false
	end
	if return_table then
		for _,v in ipairs(effects) do 
			if v.jokers and not v.jokers.card then v.jokers.card = card end
			return_table[#return_table+1] = v
		end
	else
		SMODS.trigger_effects(effects, card)
	end
end

function MagicTrick.eval_card(card, context, return_table)
	if card.playing_card then
		MagicTrick.eval_playing_card(card, context, return_table)
	else
		MagicTrick.eval_joker(card, context, return_table)
	end
end

function MagicTrick.get_all_areas(context)
	local _t = SMODS.get_card_areas("playing_cards", context)
	local _t2 = SMODS.get_card_areas("jokers", context)
	for _, area in ipairs(_t2) do
		local found_self = nil
		for __, area2 in ipairs(_t) do
			if area == area2 then found_self = true end
		end
		if not found_self then
			_t[#_t+1] = area
		end
	end
	return _t
end

local score_card_hook = SMODS.score_card
function SMODS.score_card(card, context)
	if card.playing_card then
		score_card_hook(card, context)
	else
	-- this is where jokers are played
		local joker_main_spoof = nil
		local effects = {}
		-- edition
		local eval = eval_card(card, {cardarea = context.cardarea, full_hand = G.play.cards, scoring_hand = context.scoring_hand, scoring_name = text, poker_hands = poker_hands, edition = true, pre_joker = true})
		if eval.edition then effects[#effects+1] = eval end
		
		-- first fire off a custom context
		local joker_eval, post = eval_card(card, {cardarea = G.jokers, full_hand = G.play.cards, scoring_hand = context.scoring_hand, scoring_name = text, poker_hands = poker_hands, joker_playing_card = true})
		-- if custom context fails, pretend to be joker_main
		if not next(joker_eval) then
			joker_eval, post = eval_card(card, {cardarea = G.jokers, full_hand = G.play.cards, scoring_hand = scoring_hand, scoring_name = text, poker_hands = poker_hands, joker_main = true})
			joker_main_spoof = true
		end
		
		if next(joker_eval) then
			if joker_eval.edition then joker_eval.edition = {} end
			table.insert(effects, joker_eval)
			for _, v in ipairs(post) do effects[#effects+1] = v end
			
			MagicTrick.calculate_individual_joker(card, context, effects)
			
			if joker_eval.retriggers then
				for rt = 1, #joker_eval.retriggers do
					local rt_eval, rt_post = eval_card(card, {cardarea = joker_main_spoof and G.jokers or context.cardarea, full_hand = G.play.cards, scoring_hand = scoring_hand, scoring_name = text, poker_hands = poker_hands, joker_playing_card = not joker_main_spoof and true or nil , joker_main = joker_main_spoof, retrigger_joker = true})
					table.insert(effects, {joker_eval.retriggers[rt]})
					table.insert(effects, rt_eval)
					for _, v in ipairs(rt_post) do effects[#effects+1] = v end
					MagicTrick.calculate_individual_joker(card, context, effects)
				end
			end
		end
		-- calculate edition multipliers
		local eval = eval_card(card, {cardarea = G.jokers, full_hand = G.play.cards, scoring_hand = scoring_hand, scoring_name = text, poker_hands = poker_hands, edition = true, post_joker = true})
		if eval.edition then effects[#effects+1] = eval end
		SMODS.trigger_effects(effects, card)
	end
end

function MagicTrick.calculate_individual_joker(card, context, effects)
	context.individual = true
	context.other_card = card
	
	for _, area in ipairs(MagicTrick.get_all_areas()) do
		for _, _card in ipairs(area.cards) do
			--calculate the joker individual card effects
			local eval, post = eval_card(_card, context)
			if next(eval) then
				if eval.jokers then eval.jokers.juice_card = eval.jokers.juice_card or eval.jokers.card or _card end
				table.insert(effects, eval)
				for _, v in ipairs(post) do effects[#effects+1] = v end
				if eval.retriggers then
					context.retrigger_joker = true
					for rt = 1, #eval.retriggers do
						local rt_eval, rt_post = eval_card(_card, context)
						table.insert(effects, { eval.retriggers[rt] })
						table.insert(effects, rt_eval)
						for _, v in ipairs(rt_post) do effects[#effects+1] = v end
					end
					context.retrigger_joker = nil
				end
			end
		end
	end
	
	context.individual = nil
	context.other_card = nil
end

function MagicTrick.calculate_repetitions(card, context, reps, _ret)
	--todo: write this as a calc function that calcs both repetitions and retriggers as a single calc
end