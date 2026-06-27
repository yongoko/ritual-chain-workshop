# Reflection

**What should be public, what should stay hidden, and what should be decided by
AI versus by a human in a bounty system?**

The *rules* of a bounty should be fully public: the rubric, the reward, the
deadlines, who the owner is, and the commitment of each participant — because
fairness depends on everyone being able to verify the contract enforced the same
rules for all. What should stay hidden is the *content* of each answer until the
judging is complete, since visible answers let later entrants copy and out-bid
earlier ones, which defeats the purpose of an open competition. Commit-reveal hides
answers during submission, and a Ritual-native TEE flow can keep them hidden right
up to the moment a decision is made, which is the stronger fairness guarantee.
Routine, high-volume evaluation is what AI should do: reading every submission,
scoring it against the rubric, and ranking them in a single impartial pass that no
tired human reviewer could match for consistency. But the AI's output should be
treated as a *recommendation*, not an automatic payout, because models can be
manipulated by prompt-injection inside submissions, can hallucinate, or can miss
context that only the bounty owner knows. The final, money-moving decision — and
accountability for it — should stay with a human, who reviews the AI's reasoning
and explicitly finalizes one winner. In short: make the rules and the process
transparent, keep the answers secret until the verdict, let AI do the heavy lifting
of comparison, and keep a human in the loop for the payout that has real
consequences.
