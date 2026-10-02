#!/usr/bin/env python3
"""Trailer UEFN automatique — interface graphique (double-clic sur lancer.bat)."""

import queue
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, simpledialog, ttk

from trailer_uefn.montage import (EXTENSIONS_VIDEO, MENTIONS_EPIC, RYTHMES, Clip, Options,
                                  creer_trailer, lister_clips)


class Appli(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Trailer UEFN automatique")
        self.geometry("880x760")
        self.minsize(760, 640)
        self.messages = queue.Queue()
        self.clips = []                     # [chemin, etiquette]
        self._construire()
        self.after(100, self._lire_journal)

    # ------------------------------------------------------------- interface
    def _construire(self):
        cadre = ttk.Frame(self, padding=12)
        cadre.pack(fill="both", expand=True)

        ttk.Label(cadre, text="1. Tes videos de gameplay", font=("", 11, "bold")).pack(anchor="w")
        ttk.Label(cadre, text="Double-clique une ligne pour ecrire son bandeau "
                              "(ex. FIGHT BOSS). Les clips d'un meme bandeau forment une section.",
                  foreground="#555").pack(anchor="w")
        zone = ttk.Frame(cadre)
        zone.pack(fill="x", pady=4)
        self.arbre = ttk.Treeview(zone, columns=("fichier", "bandeau"), show="headings", height=6)
        self.arbre.heading("fichier", text="Video")
        self.arbre.heading("bandeau", text="Bandeau (texte jaune)")
        self.arbre.column("fichier", width=420)
        self.arbre.column("bandeau", width=300)
        self.arbre.pack(side="left", fill="x", expand=True)
        self.arbre.bind("<Double-1>", self._editer_bandeau)
        boutons = ttk.Frame(zone)
        boutons.pack(side="left", padx=6)
        ttk.Button(boutons, text="Ajouter...", command=self._ajouter).pack(fill="x")
        ttk.Button(boutons, text="Dossier...", command=self._ajouter_dossier).pack(fill="x", pady=2)
        ttk.Button(boutons, text="Monter", command=lambda: self._deplacer(-1)).pack(fill="x")
        ttk.Button(boutons, text="Descendre", command=lambda: self._deplacer(1)).pack(fill="x", pady=2)
        ttk.Button(boutons, text="Retirer", command=self._retirer).pack(fill="x")

        ttk.Label(cadre, text="2. Ta map", font=("", 11, "bold")).pack(anchor="w", pady=(10, 0))
        grille = ttk.Frame(cadre)
        grille.pack(fill="x")
        self.v = {}

        def champ(ligne, col, libelle, cle, defaut="", largeur=30):
            ttk.Label(grille, text=libelle).grid(row=ligne, column=col, sticky="w", padx=(0, 6), pady=2)
            var = tk.StringVar(value=defaut)
            ttk.Entry(grille, textvariable=var, width=largeur).grid(row=ligne, column=col + 1,
                                                                     sticky="we", pady=2)
            self.v[cle] = var

        champ(0, 0, "Nom de la map", "titre")
        champ(0, 2, "Code de l'ile", "code", "", 18)
        champ(1, 0, "Accroche (debut)", "accroche")
        champ(1, 2, "Texte final", "final", "", 18)
        champ(2, 0, "Bandeaux (si une seule video)", "textes")
        champ(2, 2, "Badge miniature", "badge", "NEW", 18)
        ttk.Label(grille, text="  ex. MINE ORES | FIGHT BOSS | UNLOCK DRONES",
                  foreground="#555").grid(row=3, column=1, sticky="w")
        grille.columnconfigure(1, weight=1)

        ttk.Label(cadre, text="3. Style", font=("", 11, "bold")).pack(anchor="w", pady=(10, 0))
        style = ttk.Frame(cadre)
        style.pack(fill="x")
        self.v["musique"] = tk.StringVar()
        self.v["logo"] = tk.StringVar()
        self.v["image_fin"] = tk.StringVar()
        for ligne, (libelle, cle, types) in enumerate([
                ("Musique (vide = auto)", "musique", [("Audio", "*.mp3 *.wav *.ogg *.m4a *.flac")]),
                ("Logo (ouverture)", "logo", [("Image", "*.png")]),
                ("Image de fin / key art", "image_fin", [("Image", "*.png *.jpg *.jpeg *.webp")])]):
            ttk.Label(style, text=libelle).grid(row=ligne, column=0, sticky="w", pady=2)
            ttk.Entry(style, textvariable=self.v[cle]).grid(row=ligne, column=1, sticky="we", padx=6)
            ttk.Button(style, text="...", width=3,
                       command=lambda c=cle, t=types: self._choisir(c, t)).grid(row=ligne, column=2)
        style.columnconfigure(1, weight=1)

        reglages = ttk.Frame(cadre)
        reglages.pack(fill="x", pady=6)
        self.v["duree"] = tk.IntVar(value=30)
        ttk.Label(reglages, text="Duree (s)").pack(side="left")
        ttk.Spinbox(reglages, from_=15, to=90, increment=5, textvariable=self.v["duree"],
                    width=5).pack(side="left", padx=(4, 14))
        self.v["rythme"] = tk.StringVar(value="normal")
        ttk.Label(reglages, text="Rythme").pack(side="left")
        ttk.Combobox(reglages, values=list(RYTHMES), textvariable=self.v["rythme"], width=8,
                     state="readonly").pack(side="left", padx=(4, 14))
        self.v["vertical"] = tk.BooleanVar(value=False)
        ttk.Checkbutton(reglages, text="Vertical (TikTok)", variable=self.v["vertical"]).pack(side="left")
        self.v["fps60"] = tk.BooleanVar(value=True)
        ttk.Checkbutton(reglages, text="60 ips", variable=self.v["fps60"]).pack(side="left", padx=8)
        self.v["mentions"] = tk.BooleanVar(value=True)
        ttk.Checkbutton(reglages, text="Mentions Epic", variable=self.v["mentions"]).pack(side="left")
        self.v["couleur"] = tk.StringVar(value="#FFD400")
        ttk.Label(reglages, text="  Couleur").pack(side="left")
        ttk.Entry(reglages, textvariable=self.v["couleur"], width=8).pack(side="left", padx=4)

        bas = ttk.Frame(cadre)
        bas.pack(fill="x", pady=(4, 6))
        self.bouton = ttk.Button(bas, text="Creer le trailer + miniatures", command=self._lancer)
        self.bouton.pack(side="left")
        self.barre = ttk.Progressbar(bas, mode="indeterminate", length=200)
        self.barre.pack(side="left", padx=10)

        self.journal = tk.Text(cadre, height=12, state="disabled", font=("Consolas", 9))
        self.journal.pack(fill="both", expand=True)

    # ------------------------------------------------------------ evenements
    def _rafraichir(self):
        self.arbre.delete(*self.arbre.get_children())
        for chemin, etiquette in self.clips:
            self.arbre.insert("", "end", values=(Path(chemin).name, etiquette or ""))

    def _ajouter(self):
        types = [("Videos", " ".join(f"*{e}" for e in sorted(EXTENSIONS_VIDEO)))]
        fichiers = filedialog.askopenfilenames(filetypes=types)
        if fichiers:
            self.clips += [[c.chemin, c.etiquette] for c in lister_clips(fichiers)]
            self._rafraichir()

    def _ajouter_dossier(self):
        dossier = filedialog.askdirectory()
        if dossier:
            try:
                self.clips += [[c.chemin, c.etiquette] for c in lister_clips([dossier])]
            except FileNotFoundError as e:
                messagebox.showwarning("Dossier", str(e))
            self._rafraichir()

    def _selection(self):
        sel = self.arbre.selection()
        return self.arbre.index(sel[0]) if sel else None

    def _editer_bandeau(self, _evt):
        i = self._selection()
        if i is None:
            return
        texte = simpledialog.askstring("Bandeau", "Texte du bandeau pour ce clip :",
                                       initialvalue=self.clips[i][1] or "", parent=self)
        if texte is not None:
            self.clips[i][1] = texte.strip().upper() or None
            self._rafraichir()

    def _deplacer(self, sens):
        i = self._selection()
        if i is None or not 0 <= i + sens < len(self.clips):
            return
        self.clips[i], self.clips[i + sens] = self.clips[i + sens], self.clips[i]
        self._rafraichir()
        self.arbre.selection_set(self.arbre.get_children()[i + sens])

    def _retirer(self):
        i = self._selection()
        if i is not None:
            del self.clips[i]
            self._rafraichir()

    def _choisir(self, cle, types):
        chemin = filedialog.askopenfilename(filetypes=types)
        if chemin:
            self.v[cle].set(chemin)

    def _lancer(self):
        if not self.clips:
            messagebox.showwarning("Videos", "Ajoute au moins une video de gameplay.")
            return
        sortie = filedialog.asksaveasfilename(defaultextension=".mp4", initialfile="trailer.mp4",
                                              filetypes=[("Video MP4", "*.mp4")])
        if not sortie:
            return
        g = {k: v.get() for k, v in self.v.items()}
        opts = Options(
            titre=g["titre"].strip(), code=g["code"].strip(), accroche=g["accroche"].strip(),
            texte_final=g["final"].strip(),
            textes=[t.strip() for t in g["textes"].split("|") if t.strip()],
            musique=g["musique"], logo=g["logo"], image_fin=g["image_fin"],
            duree=float(g["duree"]), rythme=g["rythme"],
            format="vertical" if g["vertical"] else "horizontal", fps=60 if g["fps60"] else 30,
            accent=g["couleur"] or "#FFD400", mentions=MENTIONS_EPIC if g["mentions"] else "",
            badge=g["badge"].strip(),
        )
        clips = [list(c) for c in self.clips]
        self.bouton.state(["disabled"])
        self.barre.start(12)
        threading.Thread(target=self._travail, args=(clips, sortie, opts), daemon=True).start()

    def _travail(self, clips, sortie, opts):
        try:
            # Les bandeaux saisis dans la liste remplacent ceux lus dans les noms de fichiers
            creer_trailer([Clip(c, e) for c, e in clips], sortie, opts, journal=self.messages.put)
            self.messages.put(("fin", f"Trailer et miniatures enregistres dans :\n{Path(sortie).parent}"))
        except Exception as e:
            self.messages.put(("erreur", str(e)))

    def _lire_journal(self):
        try:
            while True:
                msg = self.messages.get_nowait()
                if isinstance(msg, tuple):
                    self.barre.stop()
                    self.bouton.state(["!disabled"])
                    (messagebox.showinfo if msg[0] == "fin" else messagebox.showerror)(
                        "Termine" if msg[0] == "fin" else "Erreur", msg[1])
                    msg = msg[1]
                self.journal.configure(state="normal")
                self.journal.insert("end", msg + "\n")
                self.journal.see("end")
                self.journal.configure(state="disabled")
        except queue.Empty:
            pass
        self.after(100, self._lire_journal)


if __name__ == "__main__":
    Appli().mainloop()
