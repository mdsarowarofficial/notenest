from pw import run
SUBJ_Y = {0: 170, 1: 218, 2: 266, 3: 314}
NOTES = [
 (0, "UML diagram types", "Design", ["Structure: class, object, component", "Behaviour: use case, sequence, activity", "A sequence diagram shows messages in time order"]),
 (0, "Software testing levels", "Testing", ["Unit, integration, system, acceptance", "Black box tests behaviour, white box tests code paths", "Regression testing re-runs old tests after a change"]),
 (1, "Normalization 1NF to 3NF", "Normalization", ["1NF: atomic values, no repeating groups", "2NF: no partial dependency on the key", "3NF: no transitive dependency"]),
 (1, "SQL joins cheat sheet", "SQL", ["INNER keeps matching rows only", "LEFT keeps every row from the left table", "FULL OUTER keeps all rows from both tables"]),
 (2, "Process scheduling algorithms", "CPU scheduling", ["FCFS is simple but causes the convoy effect", "SJF minimises average waiting time", "Round robin needs a good time quantum"]),
 (2, "Deadlock conditions", "Deadlock", ["Mutual exclusion, hold and wait", "No pre-emption, circular wait", "Break any one of the four to prevent deadlock"]),
 (3, "TCP three-way handshake", "Transport layer", ["SYN from the client", "SYN-ACK from the server", "ACK from the client, then data flows"]),
]
def f(a):
    for subj, title, topic, lines in NOTES:
        a.tap("New note", exact=True); a.page.wait_for_timeout(2200)
        a.tap("Write a note Start", exact=False); a.page.wait_for_timeout(2600)
        a.tap_xy(105, 170); a.page.wait_for_timeout(1300)
        a.tap_xy(100, SUBJ_Y[subj]); a.page.wait_for_timeout(700)
        a.tap_xy(195, 92); a.type(title)
        a.tap_xy(284, 170); a.type(topic)
        a.tap_xy(195, 430); a.page.wait_for_timeout(300)
        for i, l in enumerate(lines):
            a.type("- " + l)
            if i < len(lines) - 1: a.page.keyboard.press("Enter")
        a.page.wait_for_timeout(900)
        a.tap("Done", exact=True); a.page.wait_for_timeout(2200)
        print("made", title)
    a.shot("_n7")
if __name__ == "__main__": run(f)
