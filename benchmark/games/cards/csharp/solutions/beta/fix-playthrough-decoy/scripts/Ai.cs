namespace Lanternfen;

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

/// <summary>
/// The utility AI that plays a keeper. In its Main phase it scores every card the rules let it play: how well the card
/// spends the turn's kindling, times what the card is worth now (each from 0 to 1, so a worth of 0 vetoes a card). It
/// plays the best, or ends its Main phase when nothing beats PassScore. Rivals differ only in their weights: aggression
/// raises attacks, caution raises mending and guard. LastScores keeps the numbers behind the last choice, so "why did it
/// do that" is answered from the log. All arithmetic is in doubles, in the GDScript version's order, so both versions
/// choose the same cards.
/// </summary>
public sealed class Ai
{
    public const double PassScore = 0.1;
    public const double WinningWeight = 2.0;

    public Ai(double aggression = 1.0, double caution = 1.0)
    {
        Aggression = aggression;
        Caution = caution;
    }

    public double Aggression { get; set; }
    public double Caution { get; set; }

    /// <summary>Card id -> score, for the cards the last choice weighed.</summary>
    public Dictionary<string, double> LastScores { get; } = new();

    /// <summary>The index in the hand of the card to play, or -1 to end the Main phase.</summary>
    public int Choose(Duel duel, int seat)
    {
        LastScores.Clear();
        int best = -1;
        double bestScore = PassScore;
        List<string> hand = duel.Keepers[seat].Hand;
        for (int i = 0; i < hand.Count; i++)
        {
            if (duel.Cards.Get(hand[i]).Cost > duel.Keepers[seat].Kindling)
                continue;
            double value = Score(duel, seat, i);
            LastScores[hand[i]] = value;
            if (value > bestScore)
            {
                best = i;
                bestScore = value;
            }
        }
        return best;
    }

    /// <summary>The utility of playing a card of the hand now.</summary>
    public double Score(Duel duel, int seat, int index)
    {
        Keeper me = duel.Keepers[seat];
        Card card = duel.Cards.Get(me.Hand[index]);
        // Spending: a card that uses more of the turn's kindling wastes less of it.
        double spend = 0.5 + 0.5 * (double)card.Cost / (double)Math.Max(me.Kindling, 1);
        double value = spend * Worth(duel, seat, card);
        // Weight groups: a play that wins the duel now outranks every other.
        if (card.Effect == "bolt" && duel.Keepers[1 - seat].Light <= card.Amount)
            value *= WinningWeight;
        return value;
    }

    /// <summary>What a card is worth to a keeper in this position, from 0 (never) to 1 (now).</summary>
    public double Worth(Duel duel, int seat, Card card)
    {
        Keeper me = duel.Keepers[seat];
        Keeper foe = duel.Keepers[1 - seat];
        if (card.Kind == Cards.Wisp)
        {
            double value = Math.Clamp((card.Power * Aggression + card.Guard * Caution * 0.5) / 8.0, 0.0, 1.0);
            // A wisp the strongest wisp across would put out at once is worth less.
            int threat = duel.StrongestLane(1 - seat);
            if (threat >= 0 && foe.Row[threat]!.Power >= card.Guard)
                value *= 0.6;
            return value;
        }
        switch (card.Effect)
        {
            case "bolt":
                if (foe.Light <= card.Amount)
                    return 1.0;
                return Math.Clamp(0.3 * Aggression, 0.0, 1.0);
            case "mend":
                int missing = me.MaxLight - me.Light;
                if (missing <= 0)
                    return 0.0;
                double danger = 1.0 - (double)me.Light / (double)me.MaxLight;
                return Math.Clamp((double)Math.Min(missing, card.Amount) / (double)card.Amount * (0.2 + 0.8 * danger) * Caution, 0.0, 1.0);
            case "draw":
                if (me.Deck.Count < card.Amount || me.Hand.Count - 1 + card.Amount > Duel.HandMax)
                    return 0.0;
                return 0.45;
            case "douse":
                int lane = duel.StrongestLane(1 - seat);
                if (lane < 0)
                    return 0.0;
                Wisp target = foe.Row[lane]!;
                double kill = target.Guard <= card.Amount ? 1.0 : 0.5;
                return Math.Clamp(target.Power / 5.0 * kill * Aggression, 0.0, 1.0);
            case "rekindle":
                return duel.LastFallen(seat) >= 0 ? 0.4 : 0.0;
        }
        return 0.0;
    }

    /// <summary>The last choice's scores as one log line, best first: "flare 0.62, reed_hound 0.41, pass 0.10".</summary>
    public string Describe()
    {
        var ids = new List<string>(LastScores.Keys);
        ids.Sort((a, b) => LastScores[a] != LastScores[b] ? LastScores[b].CompareTo(LastScores[a]) : string.CompareOrdinal(a, b));
        var line = new StringBuilder();
        foreach (string id in ids)
            line.Append(id).Append(' ').Append(LastScores[id].ToString("F2", CultureInfo.InvariantCulture)).Append(", ");
        line.Append("pass ").Append(PassScore.ToString("F2", CultureInfo.InvariantCulture));
        return line.ToString();
    }

    /// <summary>
    /// Plays a duel to its end with an AI in each seat, without the game: for tests and balance checks. Returns the winner,
    /// or -1 when it did not end within maxSteps. A play the rules refuse ends that Main phase.
    /// </summary>
    public static int PlayOut(Duel duel, Ai[] ais, int maxSteps = 5000)
    {
        for (int step = 0; step < maxSteps; step++)
        {
            if (duel.Phase == Phase.Over)
                return duel.Winner;
            if (duel.Phase != Phase.Main)
            {
                duel.Advance();
                continue;
            }
            int index = ais[duel.Active].Choose(duel, duel.Active);
            if (index < 0 || !duel.Play(duel.Active, index))
                duel.EndMain();
        }
        return duel.Phase != Phase.Over ? -1 : duel.Winner;
    }
}
