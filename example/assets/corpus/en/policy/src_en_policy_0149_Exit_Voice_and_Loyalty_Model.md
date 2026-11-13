# Exit, Voice, and Loyalty Model

- source_key: src_en_policy_0149
- language: en
- domain: policy
- length_bucket: long
- collected_at: 2026-02-22
- url: https://en.wikipedia.org/wiki/Exit,_Voice,_and_Loyalty_Model

---

The Exit, Voice, Loyalty (EVL) model or Exit, Voice, Loyalty, Neglect (EVLN) is used in the fields of comparative politics and organizational behavior. It is an extensive form game used to model interactions typically involving negative changes to one player's environment by another player. These concepts first appeared in Albert Hirschman's more broadly focused 1970 book, Exit, Voice, and Loyalty: Responses to Decline in Firms, Organizations, and States. A common use in political science is between citizens and their government. Usually in this use the Citizen player is any group within a society ranging from a single individual to the citizenry as a whole.

Model
The EVL Model involves two agents and their responses to a change initiated before the game began. The first agent is commonly referred to as the Citizen and the second is commonly referred to as the Government. EVL assumes that the change implemented before the game began was performed by the Government and negatively harms the Citizen.

Formal definition
The formal definition of EVL is the following:
There are two players: 
 
 
 
 N
 =
 {
 
 Citizen
 
 ,
 
 Government
 
 }
 
 
 {\displaystyle N=\{{\text{Citizen}},{\text{Government}}\}}
 
. The 
 
 
 
 
 Citizen
 
 
 
 {\displaystyle {\text{Citizen}}}
 
 moves first, and chooses among three actions 
 
 
 
 {
 
 exit
 
 ,
 
 voice
 
 ,
 
 loyalty
 
 }
 
 
 {\displaystyle \{{\text{exit}},{\text{voice}},{\text{loyalty}}\}}
 
. If the 
 
 
 
 
 Citizen
 
 
 
 {\displaystyle {\text{Citizen}}}
 
 chooses 
 
 
 
 
 voice
 
 
 
 {\displaystyle {\text{voice}}}
 
, then 
 
 
 
 
 Government
 
 
 
 {\displaystyle {\text{Government}}}
 
 can either 
 
 
 
 
 respond
 
 
 
 {\displaystyle {\text{respond}}}
 
 or 
 
 
 
 
 ignore
 
 
 
 {\displaystyle {\text{ignore}}}
 
. If the 
 
 
 
 
 Government
 
 
 
 {\displaystyle {\text{Government}}}
 
 chooses to 
 
 
 
 
 ignore
 
 
 
 {\displaystyle {\text{ignore}}}
 
, the 
 
 
 
 
 Citizen
 
 
 
 {\displaystyle {\text{Citizen}}}
 
 then chooses between 
 
 
 
 
 exit
 
 
 
 {\displaystyle {\text{exit}}}
 
 or 
 
 
 
 
 loyalty
 
 
 
 {\displaystyle {\text{loyalty}}}
 
. Subsequent to this (and any other action choices), the game terminates.
Formally, this is represented by the set of histories 
 
 
 
 H
 =
 {
 ∅
 ,
 (
 
 exit
 
 )
 ,
 (
 
 voice
 
 )
 ,
 (
 
 loyalty
 
 )
 ,
 (
 
 voice
 
 ,
 
 respond
 
 )
 ,
 (
 
 voice
 
 ,
 
 ignore
 
 )
 ,
 (
 
 voice
 
 ,
 
 ignore
 
 ,
 
 exit
 
 )
 ,
 (
 
 voice
 
 ,
 
 ignore
 
 ,
 
 loyalty
 
 )
 }
 .
 
 
 {\displaystyle H=\{\emptyset ,({\text{exit}}),({\text{voice}}),({\text{loyalty}}),({\text{voice}},{\text{respond}}),({\text{voice}},{\text{ignore}}),({\text{voice}},{\text{ignore}},{\text{exit}}),({\text{voice}},{\text{ignore}},{\text{loyalty}})\}.}
 
 The terminal histories, upon reaching which the game terminates, is given by 
 
 
 
 Z
 =
 {
 (
 
 exit
 
 )
 ,
 (
 
 loyalty
 
 )
 ,
 (
 
 voice
 
 ,
 
 respond
 
 )
 ,
 (
 
 voice
 
 ,
 
 ignore
 
 ,
 
 exit
 
 )
 ,
 (
 
 voice
 
 ,
 
 ignore
 
 ,
 
 loyalty
 
 )
 }
 .
 
 
 {\displaystyle Z=\{({\text{exit}}),({\text{loyalty}}),({\text{voice}},{\text{respond}}),({\text{voice}},{\text{ignore}},{\text{exit}}),({\text{voice}},{\text{ignore}},{\text{loyalty}})\}.}
 
 For all other histories, one of the two players makes a move, and this is given by the player function 
 
 
 
 P
 (
 ∅
 )
 =
 
 Citizen
 
 ,
 
 P
 (
 
 voice
 
 )
 =
 
 Government
 
 ,
 
 P
 (
 
 voice
 
 ,
 
 ignore
 
 )
 =
 
 Citizen
 
 .
 
 
 {\displaystyle P(\emptyset )={\text{Citizen}},\ P({\text{voice}})={\text{Government}},\ P({\text{voice}},{\text{ignore}})={\text{Citizen}}.}
 

The utility function of the 
 
 
 
 
 Citizen
 
 
 
 {\displaystyle {\text{Citizen}}}
 
 is defined as 

 
 
 
 
 
 u
 
 C
 
 
 (
 
 exit
 
 )
 =
 E
 ,
 
 
 u
 
 C
 
 
 (
 
 loyalty
 
 )
 =
 0
 ,
 
 
 u
 
 C
 
 
 (
 
 voice
 
 ,
 
 respond
 
 )
 =
 1
 −
 c
 ,
 
 
 {\displaystyle \ u_{C}({\text{exit}})=E,\ u_{C}({\text{loyalty}})=0,\ u_{C}({\text{voice}},{\text{respond}})=1-c,}
 

 
 
 
 
 
 u
 
 C
 
 
 (
 
 voice
 
 ,
 
 ignore
 
 ,
 
 exit
 
 )
 =
 E
 −
 c
 ,
 
 
 u
 
 C
 
 
 (
 
 voice
 
 ,
 
 ignore
 
 ,
 
 loyalty
 
 )
 =
 0
 −
 c
 .
 
 
 {\displaystyle \ u_{C}({\text{voice}},{\text{ignore}},{\text{exit}})=E-c,\ u_{C}({\text{voice}},{\text{ignore}},{\text{loyalty}})=0-c.}
 

In words, the 
 
 
 
 
 Citizen
 
 
 
 {\displaystyle {\text{Citizen}}}
 
 incurs a cost of 
 
 
 
 c
 
 
 {\displaystyle c}
 
 whenever they choose to raise their 
 
 
 
 
 voice
 
 
 
 {\displaystyle {\text{voice}}}
 
, and if the 
 
 
 
 
 Government
 
 
 
 responds
 
 
 
 {\displaystyle {\text{Government}}\ {\text{responds}}}
 
, they get a payoff of 
 
 
 
 1
 
 
 {\displaystyle 1}
 
. Irrespective of this choice, they can choose to 
 
 
 
 
 exit
 
 
 
 {\displaystyle {\text{exit}}}
 
 for a payoff of 
 
 
 
 E
 
 
 {\displaystyle E}
 
 or remain 
 
 
 
 
 loyal
 
 
 
 {\displaystyle {\text{loyal}}}
 
 for payoff of zero.
Similarly, the payoff function of the 
 
 
 
 
 Government
 
 
 
 {\displaystyle {\text{Government}}}
 
 is defined as 

 
 
 
 
 
 u
 
 G
 
 
 (
 
 exit
 
 )
 =
 1
 ,
 
 
 u
 
 G
 
 
 (
 
 loyalty
 
 )
 =
 1
 +
 L
 ,
 
 
 u
 
 G
 
 
 (
 
 voice
 
 ,
 
 respond
 
 )
 =
 L
 ,
 
 
 u
 
 G
 
 
 (
 
 voice
 
 ,
 
 ignore
 
 ,
 
 exit
 
 )
 =
 1
 ,
 
 
 u
 
 G
 
 
 (
 
 voice
 
 ,
 
 ignore
 
 ,
 
 loyalty
 
 )
 =
 1
 +
 L
 .
 
 
 {\displaystyle \ u_{G}({\text{exit}})=1,\ u_{G}({\text{loyalty}})=1+L,\ u_{G}({\text{voice}},{\text{respond}})=L,\ u_{G}({\text{voice}},{\text{ignore}},{\text{exit}})=1,\ u_{G}({\text{voice}},{\text{ignore}},{\text{loyalty}})=1+L.}
 

In words, the 
 
 
 
 
 Government
 
 
 
 {\displaystyle {\text{Government}}}
 
 incurs a cost of one for 
 
 
 
 
 responding
 
 
 
 {\displaystyle {\text{responding}}}
 
 to the 
 
 
 
 
 Citizen's voiced
 
 
 
 {\displaystyle {\text{Citizen's voiced}}}
 
 concerns, and gains a payoff of 
 
 
 
 L
 
 
 {\displaystyle L}
 
 if the 
 
 
 
 
 Citizen
 
 
 
 {\displaystyle {\text{Citizen}}}
 
 does not 
 
 
 
 
 exit
 
 
 
 {\displaystyle {\text{exit}}}
 
.

Theoretical definition
The precursory policy that the Government has implemented has the effect of removing a benefit with the value of 1 from the Citizen and giving it to the Government. The value was chosen to be 1 so that all comparisons within the game can easily be converted to ratios and then adapted to other situations where the true value of the benefit is known.
In EVL, all possible actions that can be taken by the Citizen are grouped into one of three options. Exit options are those in which the Citizen accepts the loss of the benefit and instead alters their behavior to get the best possible alternative. Examples could include relocating assets to avoid a new tax, reincorporating a business to avoid new regulations, buying goods from a different store when the quality of the original diminishes, voting out the incumbent, etc. The payoff of an Exit option for the Citizen is the variable E and the Government gets to keep the 1 it took initially.
Loyalty options are ones where the Citizen chooses to put up with the new policy and not alter their behavior. The payoff for the Citizen is 0 as they decide to take the loss and the Government receives the 1 it took plus the value of the Citizen's Loyalty. The value of the Citizen's Loyalty is the variable L.
Voice options are where the Citizen makes an active effort to show their dissatisfaction with the new policy and tries to get the Government to change its mind. Examples could be lobbying, protesting, petitioning, etc. Voice options do not have immediate payoffs but are intended to give the Government a chance to Respond to the Citizen and revert the policy. In the event the Government does Respond, the payoff for the Citizen is the 1 the Government initially took minus the cost of using Voice. This cost is the variable c. If the Government chooses to Ignore then the Citizen can still Exit or remain Loyal. No matter what the Citizen chooses, they still have to bear the cost of using their Voice and so the payoff for Exit would be E - c and 0 - c for remaining Loyal. The Government would receive the payoff of L (the value of the Citizen's Loyalty) if they chose to Respond and revert the policy, 1 if they chose to Ignore and the Citizen Exits, and 1 + L if they Ignore and the Citizen chooses to remain Loyal.

Dependent/Autonomous Governments and Credible Exit Threats

In EVL, if the Government is dependent on the Loyalty of the Citizen then L > 1 and if the Government is autonomous, i.e. not dependent on the loyalty and support of the Citizen, L < 1. Examples of Government dependence could be elected officials being dependent on the support of their voters, business owners being dependent on their workers, governments being dependent on institutions for economic well-being, etc. An important note is that the value the Government places on the Loyalty from the Citizen is in relation to the benefit it took. Different Citizen players also have different possible Exit options. If the Citizens have a viable Exit option, sometimes called a credible Exit threat, then E > 0, and if the Citizen does not have any good or credible Exit options then E < 0. Along with this, the cost of using the Voice option changes depending on the Citizen player as well.

Different Outcomes

The EVL game is solved differently whether the Government is dependent or autonomous from the Citizen, whether the Citizen has or does not have a credible Exit option, and the cost of using Voice.

EVL shows that the only time a Government will Respond to the Citizen using their Voice is when the Government is dependent on the support of the Citizen (L > 1) and when the Citizen has a credible Exit option (E > 0). With all other combinations of E and L the Government will choose to Ignore the Citizen if they decide to use their Voice and so the Citizen will choose to Exit or remain Loyal instead rather than bear the cost of using Voice. Although, if the cost of using Voice (c) becomes high enough (E > 1 - c) then even a dependent Government can prevent a Citizen with a credible exit threat from using their Voice.
Depending on the values of E, L, and c for different Government and Citizen players, the Government will either enact or not enact the instigating policy. The EVL game is largely never played out in reality but is used to model why institutions and individuals with relationships like those in EVL behave the way they do. In reality the players typically do not have complete information. Typically, the game can be assumed as having a precursory step in which the Government decides whether or not to implement the policy.

Applications
Many of the applications of this theory involve the different ways in which the extensive form game resolves when the values of E, L, and c are adjusted.

Dependent Government
When the Citizen has a viable Exit option and the Government is dependent on the Loyalty of the Citizen (i.e. E > 0, L > 1) the Government would not try to take away the benefit to begin with as the game would end with as it knew it would have to Respond. A parallel can be drawn to the structural dependence of the state on capital within Structural Marxism where the state is seen as being dependent on capital for its existence and the capitalists have viable Exit options through their easily mobile assets while labor does not.
In cases where the Citizen has no viable Exit option and the Government is dependent on the Loyalty of the Citizen (i.e. E < 0, L > 1) the Citizen exercises Loyalty in the face of the environmental change. Real world examples can be drawn to the 2008 financial crisis in the United States regarding the financial bailout of the financial and automobile sectors. Within a week of Lehman Brothers declaring bankruptcy the United States Treasury drafted the Troubled Asset Relief Program which planned to spend $700 billion to buy assets from struggling banks and was passed two weeks later. The then Treasury Secretary Paulson said "you won't leave this room until you agree to take this money" to the heads of the largest banks during a meeting in Washington D.C. Ford, General Motors, and Chrysler sent their chief executives to Congress to ask for a bailout of $25 billion from the Troubled Asset Relief Program. Members of Congress initially refused the bailout and mocked the executives having flown private jets to the meeting. They later returned having carpooled and were granted $13.4 billion. The automotive industry had to go through many more hurdles to receive any funds than members of the financial sector. The government and economy were dependent on the survival of both sectors but the difference in response to each facing financial trouble can be interpreted as a difference in Exit option between the two. The automotive sector has much less mobile assets as factories take much longer to move outside the country compared to financial institutions and so can be thought of as having a much weaker Exit option.
Other examples include political parties who require the support of certain groups to get elected but those groups have no viable alternative for whom to vote for. In this scenario the political party assumes the role of the Government and the group is the Citizen. The Government is dependent on the Citizen but the Citizen is without a viable Exit option (i.e. L > 1, E < 0).

Protests
One of the most obvious ways Citizens can use Voice is by protesting. The EVL Model predicts that the Citizen will only use their Voice if they have a viable Exit option and the Government is dependent (E > 0, L > 1). However, if the Government knows the Citizen will use Voice and force it to respond and revert the change it made, the Government would not enact the change in the first place. The EVL Model explains that the only time protests or other forms of Voice would be observed is when the Government does not know whether the Citizen has a credible Exit option (i.e. the Government does not know E > 0) but knows it's dependent, or when the Citizen does not know that the Government is autonomous (i.e.the Citizen does not know L < 1).

Exit, Voice, Loyalty, Neglect Model

Exit
This includes leaving the organization, transferring to another work unit, or at least trying to get away from the unsatisfactory situation. The general theory is that job dissatisfaction builds over time and is eventually strong enough to motivate employees to search for better work opportunities elsewhere. This is likely true to some extent, but the most recent opinion is that specific 'shock events' quickly energize employees to think about and engage in exit behavior. For example, the emotion reaction you experience to an unfair management decision or a conflict episode with a co-worker motivates you to look at job ads and speak to friends about job opportunities where they work. This begins the process of realigning your self-concept more with another company than with your current employer.

Voice
Voice refers to any attempt to change, rather than escape from, the dissatisfying situation. Voice can be constructive response, such as recommending ways for management to improve the situation, or it can be more confrontational, such as by filing formal grievances. In the extreme, some employees might engage in counterproductive behaviors to get attention and force changes in the organization.

Loyalty
According to A. O. Hirschman, the author of Exit, Voice, and Loyalty, the loyalty of a member to the organization he belongs to is higher when the entrance costs (physical, moral, material, or cognitive) are higher. Loyalty would be characterized as passively waiting for conditions to improve.

Neglect
Neglect includes reducing work efforts, paying less attention to quality, and increasing absenteeism and lateness. It is generally considered a passive activity that has negative consequences for the organization. The Neglect response is passively allowing for conditions to worsen.

References
