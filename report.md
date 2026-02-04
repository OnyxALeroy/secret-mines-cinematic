# Rapport de Projet : Le Donjon Procédural "Purple Haze"

## 1. Lien vers le Shader

Lien Shadertoy : [Insérer le lien vers votre shader ici une fois créé]

## 2. Description de la scène et respect des consignes

La scène représente un couloir de donjon infini, généré de manière procédurale. L'ambiance est sombre et mystérieuse, éclairée par des lanternes suspendues émettant une lumière violette. Le couloir serpente grâce à une déformation de l'espace (domain bending).

Voici comment les points imposés ont été implémentés :

1. **Plusieurs sources de lumière** : La scène est éclairée par une infinité de lanternes générées procéduralement le long du chemin. Dans la boucle de rendu (getLighting), nous itérons sur les lanternes les plus proches de la caméra (index courant ± 1) pour calculer leur contribution lumineuse. La lumière est ponctuelle, colorée en violet profond (vec3(0.35, 0.05, 0.7)), avec une atténuation quadratique ajustée pour porter loin dans le couloir.

2. **Déplacement de la caméra** : La caméra avance automatiquement le long de l'axe Z négatif en fonction du temps (iTime).
   
   Code : `vec3 ro = vec3(getPath(zPos).x, 0.0, zPos);`
   
   La fonction getPath(z) utilise un sinus pour courber la trajectoire de la caméra et du monde, donnant l'impression que le donjon serpente. La cible de la caméra (target) est légèrement décalée en avant pour anticiper le virage.

3. **Un disque découpé dans un plan (CSG)** : Les miroirs (ovales plutôt que circulaires) sont créés en soustrayant un disque plus petit à un disque plus grand. Il s'agit donc bien de disques découpés dans un plan.

4. **Un cylindre** : Les barreaux verticaux de la cage de la lanterne sont réalisés à l'aide d'une SDF de cylindre capé (sdCappedCylinder).
   
   Ils sont répétés angulairement (tous les 60 degrés) autour du centre de la lanterne grâce à une manipulation des coordonnées polaires (atan, mod).

5. **Un miroir (plan)** : Des miroirs rectangulaires sont placés sur les murs entre les lanternes.
   
   Matériau : Ils possèdent l'ID ID_MIRROR.
   
   Implémentation : Dans mainImage, si le rayon frappe un miroir, un rayon secondaire est lancé (reflect(rd, n)) pour calculer la couleur réfléchie. La réflectivité est gérée par un calcul de Fresnel métallique (pow(1.0 - dot, 5.0)), rendant le reflet plus intense aux angles rasants.

6. **Un objet articulé (au moins 2 articulations)** : L'objet articulé est la lanterne suspendue.
   
   - **Articulation 1 (Support au Mur)** : La chaîne est attachée à un support fixe.
   - **Articulation 2 (Chaîne)** : La chaîne oscille selon un angle (angles.x) calculé via des fonctions sinusoïdales basées sur le temps.
   - **Articulation 3 (Corps de la lanterne)** : Le corps de la lanterne oscille avec un second angle (angles.y) relatif à la chaîne, créant un mouvement de balancier composite réaliste.

7. **Effets avancés (Toon Shading & Soft Shadows)** : J'ai choisi d'implémenter deux effets pour donner un style "comic book" sombre :
   
   - **Soft Shadows (Ombres douces)** : Implémentées via du Raymarching secondaire vers la source de lumière. L'ombre est calculée en mesurant la distance minimale (h) du rayon d'ombre par rapport à la géométrie (k * h / t).
   - **Toon Shading (Cel-shading)** : Au lieu d'un dégradé de lumière lisse (dot(N,L)), j'utilise smoothstep pour quantifier la lumière en bandes distinctes (ombre, mi-teinte, lumière), donnant un aspect "peint". Les reflets spéculaires sont également coupés net pour faire des points de brillance stylisés.

## 3. Explication du code de l'objet articulé

Le mouvement de la lanterne repose sur une hiérarchie de transformations spatiales appliquées au vecteur de position p dans la fonction map.

**Génération des angles** : La fonction getLanternAngles(id, time) génère deux angles (a1, a2) basés sur des sinusoïdales. Chaque lanterne a un uniqueID (basé sur sa position Z) qui sert de "graine" (seed) à une fonction de hachage (hash). Cela permet à chaque lanterne de se balancer à une vitesse et une phase légèrement différentes, évitant un aspect robotique uniforme.

**Transformation hiérarchique (Forward Kinematics inverse)** : Dans le Raymarching, pour bouger un objet, on applique la rotation inverse à l'espace.

- **Étape 1 (La chaîne)** : On définit le point de pivot de la chaîne (pChainSys). On applique la rotation rot(angles.x) à l'espace. Tout ce qui est défini après cette ligne subira cette rotation. On dessine ensuite les maillons de la chaîne le long de l'axe Y négatif transformé.

- **Étape 2 (Le corps)** : On se déplace vers le bas de la chaîne (pL.y += chainLength). On applique ensuite la seconde rotation rot(angles.y). Le corps de la lanterne (toit, cage, base) est défini dans ce nouvel espace.

Ainsi, le corps de la lanterne hérite de la rotation de la chaîne (angles.x) et y ajoute la sienne (angles.y), créant une articulation double.

## 4. Difficultés rencontrées

J'ai rencontré plusieurs difficultés techniques lors de la réalisation de ce projet :

1. **Artefacts d'ombres (Self-shadowing)** : Au début, l'implémentation des Soft Shadows créait des taches noires irréalistes sur le mur directement derrière les lanternes. La lanterne projetait une ombre sur le mur situé à quelques centimètres d'elle, ce qui bouchait la lumière.
   
   **Solution** : J'ai séparé la fonction de distance en deux : map(p) (tout la scène) et mapStatic(p) (uniquement murs, sol, piliers). La fonction d'ombre softShadow utilise mapStatic. Ainsi, la lanterne est considérée comme transparente pour le calcul des ombres, ce qui permet à sa lumière d'éclairer le mur derrière elle, tout en permettant aux piliers de projeter des ombres correctes sur le sol.

2. **Rendu des réflexions** : Les reflets dans les miroirs et sur le sol (qui est humide/poli) étaient initialement flous ou invisibles.
   
   **Solution** : Le problème venait de l'aliasing dû à la distance (le trajet rayon -> miroir -> mur est long) et à une texture de mur trop fine. J'ai corrigé cela en augmentant l'échelle de la texture procédurale des murs (uv *= 2.5 au lieu de 5.0) et en augmentant l'intensité lumineuse globale pour que les détails soient visibles même après l'atténuation de la réflexion. J'ai aussi ajusté la courbe de Fresnel pour donner un aspect métallique aux miroirs et verni au sol.

3. **Placement des objets dans un monde courbe** : Faire suivre aux miroirs et aux lanternes la courbure du couloir a été complexe. Initialement, lors de la séparation des fonctions de map pour les ombres, j'avais oublié d'appliquer la courbure (p.x -= getPath(p.z)) aux objets dynamiques, ce qui les faisait "flotter" hors des murs. Il a fallu s'assurer que la déformation de l'espace soit appliquée uniformément au tout début de chaque calcul de distance.

---

*Sujet : [PROJET TNCY] Rapport de Projet - Graphisme par Ordinateur*  
*Étudiant : [VOTRE NOM ET PRÉNOM]*  
*Date : [DATE]*
