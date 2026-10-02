// Trailer Studio : logique de l'interface (aucune dependance externe).

const $ = (sel, racine = document) => racine.querySelector(sel);
const $$ = (sel, racine = document) => [...racine.querySelectorAll(sel)];

const etat = {
  clips: [],            // { cle, id, nom, duree, apercu, etiquette, chargement, progression }
  musique: null,        // { id, nom, bpm, drop }
  image_fin: null,      // { id, nom, url }
  logo: null,
  textes: [],
  rythme: "normal",
  intensite: "normal",
  format: "horizontal",
  couleur: "#FFD400",
  tache: null,
};
let compteurCle = 0;

// ------------------------------------------------------------- utilitaires

function mmss(secondes) {
  const s = Math.max(0, Math.round(secondes));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

function toast(message, type = "info") {
  const el = document.createElement("div");
  el.className = `toast ${type === "erreur" ? "erreur" : ""}`;
  el.innerHTML = `<svg class="ic"><use href="#${type === "erreur" ? "i-alerte" : "i-valide"}"/></svg><span></span>`;
  el.querySelector("span").textContent = message;
  $("#toasts").append(el);
  setTimeout(() => { el.classList.add("sort"); setTimeout(() => el.remove(), 300); }, type === "erreur" ? 6000 : 3200);
}

function envoyer(fichier, type, surProgression) {
  return new Promise((resoudre, rejeter) => {
    const xhr = new XMLHttpRequest();
    xhr.open("POST", `/api/envoi?type=${type}&nom=${encodeURIComponent(fichier.name)}`);
    xhr.upload.onprogress = (e) => e.lengthComputable && surProgression?.(e.loaded / e.total);
    xhr.onload = () => {
      let rep = {};
      try { rep = JSON.parse(xhr.responseText); } catch { /* reponse vide */ }
      xhr.status === 200 ? resoudre(rep) : rejeter(new Error(rep.erreur || "Envoi impossible"));
    };
    xhr.onerror = () => rejeter(new Error("Le studio ne répond plus. Relance lancer.bat."));
    xhr.send(fichier);
  });
}

async function api(chemin, donnees) {
  const rep = await fetch(chemin, donnees === undefined ? {} : {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(donnees),
  });
  const json = await rep.json().catch(() => ({}));
  if (!rep.ok) throw new Error(json.erreur || "Erreur du studio");
  return json;
}

// Couleur secondaire : meme teinte decalee, pour des degrades harmonieux
function decalerTeinte(hex, decalage) {
  const n = parseInt(hex.slice(1), 16);
  let r = (n >> 16) / 255, g = ((n >> 8) & 255) / 255, b = (n & 255) / 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2;
  let h = 0, s = 0;
  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
    h *= 60;
  }
  h = (h + decalage + 360) % 360;
  const k = (m) => (m + h / 30) % 12, a = s * Math.min(l, 1 - l);
  const f = (m) => Math.round(255 * (l - a * Math.max(-1, Math.min(k(m) - 3, 9 - k(m), 1))));
  return `#${[f(0), f(8), f(4)].map((v) => v.toString(16).padStart(2, "0")).join("")}`;
}

// ------------------------------------------------------------ memorisation

const MEMO = "trailer-studio-reglages";
function sauver() {
  const valeurs = { rythme: etat.rythme, intensite: etat.intensite, format: etat.format, couleur: etat.couleur, textes: etat.textes };
  $$("[data-memo]").forEach((el) => { valeurs[el.id] = el.type === "checkbox" ? el.checked : el.value; });
  try { localStorage.setItem(MEMO, JSON.stringify(valeurs)); } catch { /* stockage indisponible */ }
}
function restaurer() {
  let valeurs = {};
  try { valeurs = JSON.parse(localStorage.getItem(MEMO) || "{}"); } catch { /* ignore */ }
  $$("[data-memo]").forEach((el) => {
    if (!(el.id in valeurs)) return;
    if (el.type === "checkbox") el.checked = !!valeurs[el.id]; else el.value = valeurs[el.id];
  });
  if (valeurs.rythme) choisirSegment("rythme", valeurs.rythme);
  if (valeurs.intensite) choisirSegment("intensite", valeurs.intensite);
  if (valeurs.format) choisirFormat(valeurs.format);
  if (valeurs.couleur) choisirCouleur(valeurs.couleur);
  if (Array.isArray(valeurs.textes)) { etat.textes = valeurs.textes; dessinerPuces(); }
}

// ------------------------------------------------------------------- clips

function ajouterClips(fichiers) {
  const videos = [...fichiers].filter((f) => f.type.startsWith("video/") || /\.(mp4|mov|mkv|avi|webm|m4v)$/i.test(f.name));
  if (!videos.length) return toast("Ces fichiers ne sont pas des vidéos.", "erreur");
  for (const fichier of videos) {
    const clip = { cle: ++compteurCle, nom: fichier.name, chargement: true, progression: 0, etiquette: "" };
    etat.clips.push(clip);
    envoyer(fichier, "clip", (p) => {
      clip.progression = p;
      const barre = $(`[data-cle="${clip.cle}"] .barre-envoi span`);
      if (barre) barre.style.width = `${Math.round(p * 100)}%`;
      const txt = $(`[data-cle="${clip.cle}"] .texte-envoi`);
      if (txt) txt.textContent = p < 1 ? `Envoi ${Math.round(p * 100)} %` : "Analyse…";
    }).then((fiche) => {
      Object.assign(clip, fiche, { chargement: false });
      dessinerClips();
    }).catch((e) => {
      etat.clips = etat.clips.filter((c) => c !== clip);
      toast(`${fichier.name} : ${e.message}`, "erreur");
      dessinerClips();
    });
  }
  dessinerClips();
}

function dessinerClips() {
  const liste = $("#liste-clips");
  const unique = etat.clips.length === 1;
  liste.replaceChildren(...etat.clips.map((clip, i) => {
    const li = document.createElement("li");
    li.className = "clip";
    li.dataset.cle = clip.cle;
    li.innerHTML = `
      <div class="clip-image" draggable="${!clip.chargement}">
        <span class="clip-rang">${i + 1}</span>
        <button type="button" class="clip-retirer" aria-label="Retirer"><svg class="ic"><use href="#i-croix"/></svg></button>
        <span class="clip-duree">${clip.duree ? mmss(clip.duree) : "…"}</span>
      </div>
      <div class="clip-corps">
        <p class="clip-nom"></p>
        <input class="clip-etiquette" type="text" maxlength="32" placeholder="Bandeau · ex. FIGHT BOSS" ${unique ? "hidden" : ""}>
      </div>
      ${clip.chargement ? `<div class="clip-chargement"><span class="texte-envoi">Envoi ${Math.round(clip.progression * 100)} %</span><div class="barre-envoi"><span style="width:${Math.round(clip.progression * 100)}%"></span></div></div>` : ""}`;
    if (clip.apercu) $(".clip-image", li).style.backgroundImage = `url("${clip.apercu}")`;
    $(".clip-nom", li).textContent = clip.nom;
    $(".clip-nom", li).title = clip.nom;
    const entree = $(".clip-etiquette", li);
    entree.value = clip.etiquette || "";
    entree.addEventListener("input", () => { clip.etiquette = entree.value.toUpperCase(); majApercu(); });
    $(".clip-retirer", li).addEventListener("click", () => {
      etat.clips = etat.clips.filter((c) => c !== clip);
      dessinerClips();
    });
    brancherGlisser(li, clip);
    return li;
  }));

  const nb = etat.clips.length;
  $("#compteur-clips").hidden = !nb;
  $("#compteur-clips").textContent = `${nb} clip${nb > 1 ? "s" : ""}`;
  $("#depot-clips").classList.toggle("compact", nb > 0);
  $("#astuce-ordre").hidden = nb < 2;
  $("#bloc-textes").hidden = !unique;
  majApercu();
}

let enGlisse = null;
function brancherGlisser(li, clip) {
  const poignee = $(".clip-image", li);
  poignee.addEventListener("dragstart", (e) => {
    enGlisse = clip;
    e.dataTransfer.effectAllowed = "move";
    e.dataTransfer.setData("text/plain", String(clip.cle));
    e.dataTransfer.setDragImage(li, 40, 30);
    requestAnimationFrame(() => li.classList.add("traine"));
  });
  poignee.addEventListener("dragend", () => { enGlisse = null; $$(".clip").forEach((c) => c.classList.remove("traine", "cible")); });
  li.addEventListener("dragover", (e) => {
    if (!enGlisse || enGlisse === clip) return;
    e.preventDefault();
    li.classList.add("cible");
  });
  li.addEventListener("dragleave", () => li.classList.remove("cible"));
  li.addEventListener("drop", (e) => {
    if (!enGlisse || enGlisse === clip) return;
    e.preventDefault();
    e.stopPropagation();
    const de = etat.clips.indexOf(enGlisse), vers = etat.clips.indexOf(clip);
    etat.clips.splice(de, 1);
    etat.clips.splice(vers, 0, enGlisse);
    enGlisse = null;
    dessinerClips();
  });
}

// ------------------------------------------------------- bandeaux (1 video)

function dessinerPuces() {
  const boite = $("#etiquettes"), saisie = $("#saisie-etiquette");
  $$(".puce", boite).forEach((p) => p.remove());
  etat.textes.forEach((texte, i) => {
    const puce = document.createElement("span");
    puce.className = "puce";
    puce.innerHTML = `<span></span><button type="button" aria-label="Retirer"><svg class="ic"><use href="#i-croix"/></svg></button>`;
    puce.firstChild.textContent = texte;
    puce.querySelector("button").addEventListener("click", () => { etat.textes.splice(i, 1); dessinerPuces(); });
    boite.insertBefore(puce, saisie);
  });
  majApercu();
  sauver();
}

// ------------------------------------------------------------------ tuiles

function brancherTuile(cle, type) {
  const tuile = $(`#tuile-${cle}`), entree = $("input", tuile);
  const petit = $("small", tuile), defaut = petit.textContent, icone = $(".tuile-icone", tuile);
  const vider = () => {
    etat[cle] = null;
    tuile.classList.remove("rempli", "charge");
    icone.classList.remove("avec-image");
    icone.style.backgroundImage = "";
    petit.textContent = defaut;
    entree.value = "";
    majApercu();
  };
  const charger = async (fichier) => {
    tuile.classList.add("charge");
    petit.textContent = "Envoi…";
    try {
      const fiche = await envoyer(fichier, type, (p) => { petit.textContent = p < 1 ? `Envoi ${Math.round(p * 100)} %` : (type === "musique" ? "Analyse du tempo…" : "Préparation…"); });
      etat[cle] = fiche;
      tuile.classList.add("rempli");
      if (type === "musique") {
        petit.textContent = `${fiche.bpm} BPM${fiche.drop ? ` · drop à ${mmss(fiche.drop)}` : ""}`;
        toast(`Musique analysée : ${fiche.bpm} BPM`);
      } else {
        petit.textContent = fiche.nom;
        icone.classList.add("avec-image");
        icone.style.backgroundImage = `url("${fiche.url}")`;
      }
    } catch (e) {
      vider();
      toast(e.message, "erreur");
    }
    tuile.classList.remove("charge");
    majApercu();
  };
  entree.addEventListener("change", () => entree.files[0] && charger(entree.files[0]));
  $(".tuile-retirer", tuile).addEventListener("click", (e) => { e.preventDefault(); e.stopPropagation(); vider(); });
  tuile.addEventListener("dragover", (e) => { e.preventDefault(); e.stopPropagation(); tuile.classList.add("survol"); });
  tuile.addEventListener("dragleave", () => tuile.classList.remove("survol"));
  tuile.addEventListener("drop", (e) => {
    e.preventDefault(); e.stopPropagation(); tuile.classList.remove("survol");
    if (e.dataTransfer.files[0]) charger(e.dataTransfer.files[0]);
  });
}

// --------------------------------------------------------------- reglages

function choisirSegment(groupe, valeur) {
  const boutons = $$(`#${groupe} button`);
  const i = Math.max(0, boutons.findIndex((b) => b.dataset.valeur === valeur));
  boutons.forEach((b, j) => b.classList.toggle("actif", j === i));
  $(`#${groupe}`).style.setProperty("--i", i);
  etat[groupe] = boutons[i].dataset.valeur;
}

function choisirFormat(valeur) {
  etat.format = valeur === "vertical" ? "vertical" : "horizontal";
  $$("#format button").forEach((b) => b.classList.toggle("actif", b.dataset.valeur === etat.format));
  $("#ecran").classList.toggle("vertical", etat.format === "vertical");
  majApercu();
}

function choisirCouleur(hex) {
  etat.couleur = hex.toUpperCase();
  const racine = document.documentElement.style;
  racine.setProperty("--accent", etat.couleur);
  racine.setProperty("--accent-2", decalerTeinte(etat.couleur, -32));
  let trouve = false;
  $$("#couleurs button").forEach((b) => {
    const actif = b.dataset.valeur.toUpperCase() === etat.couleur;
    trouve ||= actif;
    b.classList.toggle("actif", actif);
  });
  const libre = $(".couleur-libre");
  libre.classList.toggle("actif", !trouve);
  libre.style.setProperty("--c", etat.couleur);
  $("#couleur-libre").value = etat.couleur.toLowerCase();
}

function majCurseur(entree) {
  const p = ((entree.value - entree.min) / (entree.max - entree.min)) * 100;
  entree.style.setProperty("--p", `${p}%`);
}

function formaterCode(valeur) {
  const chiffres = valeur.replace(/\D/g, "").slice(0, 12);
  return chiffres.replace(/(\d{4})(?=\d)/g, "$1-");
}

// ------------------------------------------------------------------ apercu

function majApercu() {
  const titre = $("#titre").value.trim();
  const code = $("#code").value.trim();
  const premiere = etat.clips.length === 1 ? etat.textes[0] : etat.clips.find((c) => c.etiquette)?.etiquette;
  $("#mock-bandeau").textContent = (premiere || "FIGHT BOSS").toUpperCase();
  $("#mock-titre").textContent = (titre || "Ma map").toUpperCase();
  $("#mock-code").textContent = code || "1234-5678-9012";
  $("#mock-appel").textContent = ($("#appel").value.trim() || "PLAY NOW!").toUpperCase();
  $("#mock-appel").hidden = !$("#appel").value.trim();

  const voirFin = $("#ecran").classList.contains("voir-fin");
  const image = voirFin && etat.image_fin ? etat.image_fin.url : etat.clips.find((c) => c.apercu)?.apercu;
  const fond = $("#ecran-fond");
  fond.classList.toggle("image", !!image);
  fond.style.setProperty("--image", image ? `url("${image}")` : "none");

  const prets = etat.clips.filter((c) => !c.chargement);
  const total = prets.reduce((s, c) => s + (c.duree || 0), 0);
  $("#resume-clips").textContent = etat.clips.length ? String(etat.clips.length) : "—";
  $("#resume-gameplay").textContent = total ? mmss(total) : "—";
  $("#resume-musique").textContent = etat.musique ? `${etat.musique.bpm} BPM` : "Générée";
  $("#resume-musique").title = etat.musique?.nom || "";
  const dims = etat.format === "vertical" ? "1080×1920" : "1920×1080";
  $("#resume-sortie").textContent = `${dims} · ${$("#fps60").checked ? 60 : 30} i/s`;

  const charge = etat.clips.some((c) => c.chargement) || $$(".tuile.charge").length > 0;
  const pret = prets.length > 0 && !charge && !etat.tache;
  $("#bouton-creer").disabled = !pret;
  $("#note-creer").textContent = !etat.clips.length ? "Ajoute au moins une vidéo pour commencer."
    : charge ? "Envoi des fichiers en cours…"
    : !titre && !$("#version_ile").checked ? "Astuce : écris le nom de ta map pour le titre animé et la carte de fin."
    : `Environ ${Math.max(1, Math.round(($("#duree").value * ($("#fps60").checked ? 4 : 2)) / 60))} min de rendu · tout reste sur ton PC`;
}

// ------------------------------------------------------------------- rendu

async function creer() {
  const options = {
    titre: $("#titre").value, code: $("#code").value, accroche: $("#accroche").value,
    final: $("#final").value, badge: $("#badge").value, appel: $("#appel").value,
    intensite: etat.intensite, bruitages: $("#bruitages").checked, version_ile: $("#version_ile").checked,
    textes: etat.clips.length === 1 ? etat.textes : [],
    duree: Number($("#duree").value), rythme: etat.rythme, vertical: etat.format === "vertical",
    fps60: $("#fps60").checked, mentions: $("#mentions").checked, couleur: etat.couleur,
    volume_jeu: Number($("#volume").value) / 100,
  };
  const donnees = {
    clips: etat.clips.map((c) => ({ id: c.id, etiquette: etat.clips.length === 1 ? "" : c.etiquette })),
    musique: etat.musique?.id, logo: etat.logo?.id, image_fin: etat.image_fin?.id, options,
  };
  try {
    const { id } = await api("/api/creer", donnees);
    etat.tache = id;
    afficherModale("rendu");
    majAnneau(0, "Préparation…", 0, []);
    suivre(id);
  } catch (e) {
    toast(e.message, "erreur");
  }
  majApercu();
}

function afficherModale(nom) {
  $("#voile").hidden = false;
  $("#modale-rendu").hidden = nom !== "rendu";
  $("#modale-resultat").hidden = nom !== "resultat";
  $("#modale-erreur").hidden = nom !== "erreur";
  document.body.style.overflow = "hidden";
}

function fermerModale() {
  $("#voile").hidden = true;
  $("#video-resultat").pause();
  document.body.style.overflow = "";
  etat.tache = null;
  majApercu();
}

function majAnneau(p, etape, ecoule, journal) {
  $("#anneau-plein").style.strokeDashoffset = 326.7 * (1 - p);
  $("#anneau-valeur").textContent = `${Math.round(p * 100)} %`;
  $("#rendu-etape").textContent = etape;
  const reste = p > 0.08 ? ecoule / p - ecoule : null;
  $("#rendu-temps").textContent = `${mmss(ecoule)} écoulé${reste ? ` · encore ~${mmss(reste)}` : ""}`;
  const pre = $("#journal");
  const enBas = pre.scrollTop + pre.clientHeight >= pre.scrollHeight - 8;
  pre.textContent = journal.join("\n");
  if (enBas) pre.scrollTop = pre.scrollHeight;
}

async function suivre(id) {
  let t;
  try {
    t = await api(`/api/etat?id=${id}`);
  } catch (e) {
    return setTimeout(() => suivre(id), 1500);
  }
  majAnneau(t.progression, t.etape, t.ecoule, t.journal);
  if (t.statut === "en_cours") return setTimeout(() => suivre(id), 700);
  if (t.statut === "erreur") {
    $("#erreur-message").textContent = t.erreur;
    afficherModale("erreur");
    etat.tache = null;
    return;
  }
  const titre = $("#titre").value.trim();
  $("#resultat-titre").textContent = titre ? `${titre} — ${mmss(t.ecoule)} de rendu` : `Rendu en ${mmss(t.ecoule)}`;
  const video = $("#video-resultat");
  video.poster = t.miniatures[0] ? `${t.miniatures[0]}?v=${Date.now()}` : "";
  video.src = `${t.video}?v=${Date.now()}`;
  video.classList.toggle("vertical", etat.format === "vertical");
  $("#telecharger-video").href = `${t.video}?telecharger=1`;
  $("#miniatures").replaceChildren(...t.miniatures.map((url, i) => {
    const a = document.createElement("a");
    a.href = `${url}?telecharger=1`;
    a.innerHTML = `<img alt="Miniature ${i + 1}" loading="lazy">`;
    a.firstChild.src = `${url}?v=${Date.now()}`;
    return a;
  }));
  afficherModale("resultat");
  $("#ouvrir-dossier").onclick = () => api("/api/ouvrir", { id }).catch((e) => toast(e.message, "erreur"));
  toast("Ton trailer est prêt !");
}

// ------------------------------------------------------------- demarrage

function demarrer() {
  // Clips : depot, parcourir, et glisser n'importe ou sur la page
  const depot = $("#depot-clips");
  $("#entree-clips").addEventListener("change", (e) => { ajouterClips(e.target.files); e.target.value = ""; });
  let profondeur = 0;
  window.addEventListener("dragenter", (e) => { if (e.dataTransfer?.types.includes("Files")) { profondeur++; depot.classList.add("survol"); } });
  window.addEventListener("dragleave", () => { if (--profondeur <= 0) { profondeur = 0; depot.classList.remove("survol"); } });
  window.addEventListener("dragover", (e) => e.preventDefault());
  window.addEventListener("drop", (e) => {
    e.preventDefault();
    profondeur = 0;
    depot.classList.remove("survol");
    if (e.dataTransfer?.files.length) ajouterClips(e.dataTransfer.files);
  });

  brancherTuile("musique", "musique");
  brancherTuile("image_fin", "image");
  brancherTuile("logo", "image");

  // Bandeaux (une seule video)
  $("#saisie-etiquette").addEventListener("keydown", (e) => {
    const saisie = e.target;
    if ((e.key === "Enter" || e.key === ",") && saisie.value.trim()) {
      e.preventDefault();
      etat.textes.push(saisie.value.trim().toUpperCase());
      saisie.value = "";
      dessinerPuces();
    } else if (e.key === "Backspace" && !saisie.value && etat.textes.length) {
      etat.textes.pop();
      dessinerPuces();
    }
  });
  $("#etiquettes").addEventListener("click", () => $("#saisie-etiquette").focus());

  // Reglages
  for (const groupe of ["rythme", "intensite"]) {
    $(`#${groupe}`).style.setProperty("--n", 3);
    $$(`#${groupe} button`).forEach((b) => b.addEventListener("click", () => { choisirSegment(groupe, b.dataset.valeur); sauver(); }));
  }
  $$("#format button").forEach((b) => b.addEventListener("click", () => { choisirFormat(b.dataset.valeur); sauver(); }));
  $$("#couleurs button").forEach((b) => b.addEventListener("click", () => { choisirCouleur(b.dataset.valeur); sauver(); }));
  $("#couleur-libre").addEventListener("input", (e) => { choisirCouleur(e.target.value); sauver(); });
  $("#code").addEventListener("input", (e) => { e.target.value = formaterCode(e.target.value); });
  $$("[data-memo]").forEach((el) => el.addEventListener("input", () => { sauver(); majApercu(); }));
  $$("[data-memo]").forEach((el) => el.addEventListener("change", sauver));
  const sorties = { duree: (v) => `${v} s`, volume: (v) => `${v} %` };
  for (const [id, format] of Object.entries(sorties)) {
    const entree = $(`#${id}`);
    const maj = () => { $(`#valeur-${id}`).textContent = format(entree.value); majCurseur(entree); };
    entree.addEventListener("input", maj);
    entree.majAffichage = maj;
  }

  // Apercu
  $$("#onglets-apercu button").forEach((b, i) => b.addEventListener("click", () => {
    $$("#onglets-apercu button").forEach((x) => x.classList.toggle("actif", x === b));
    $("#onglets-apercu").style.setProperty("--i", i);
    $("#ecran").classList.toggle("voir-fin", b.dataset.vue === "fin");
    $$(".vue").forEach((v) => v.classList.toggle("actif", v.classList.contains(`vue-${b.dataset.vue}`)));
    majApercu();
  }));

  // Rendu
  $("#bouton-creer").addEventListener("click", creer);
  $("#fermer-resultat").addEventListener("click", fermerModale);
  $("#nouvelle-version").addEventListener("click", () => { fermerModale(); toast("Change un réglage puis relance : chaque version est différente."); });
  $("#fermer-erreur").addEventListener("click", fermerModale);
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && !$("#voile").hidden && $("#modale-rendu").hidden) fermerModale();
  });

  // Forme d'onde decorative de la vitrine (un temps marque sur quatre)
  const onde = $("#onde");
  if (onde) {
    onde.replaceChildren(...Array.from({ length: 64 }, (_, i) => {
      const barre = document.createElement("span");
      const h = 22 + 70 * Math.abs(Math.sin(i * 1.7) * Math.cos(i * 0.31)) + (i % 4 === 0 ? 18 : 0);
      barre.style.setProperty("--h", `${Math.min(100, h)}%`);
      if (i % 4 === 0) barre.className = "temps";
      return barre;
    }));
  }

  restaurer();
  $("#duree").majAffichage();
  $("#volume").majAffichage();
  dessinerClips();

  api("/api/sante").then((s) => {
    const el = $("#etat-systeme");
    el.classList.add(s.ffmpeg ? "ok" : "ko");
    el.lastElementChild.textContent = s.ffmpeg ? "Studio prêt" : "ffmpeg manquant";
    if (!s.ffmpeg) toast(s.message, "erreur");
  }).catch(() => {
    $("#etat-systeme").classList.add("ko");
    $("#etat-systeme").lastElementChild.textContent = "Studio hors ligne";
  });
}

demarrer();
