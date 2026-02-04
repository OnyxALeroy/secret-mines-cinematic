#ifdef GL_ES
precision highp float;
#endif

uniform vec3 iResolution;
uniform float iTime;

// -------------------------------------------------------------------------
// CONFIGURATION
// -------------------------------------------------------------------------
#define MAX_STEPS 128
#define MAX_DIST 80.0
#define SURF_DIST 0.001
#define REFLECTION_STEPS 80
#define PI 3.14159265

// Material IDs
#define ID_NONE 0.0
#define ID_FLOOR 1.0
#define ID_CEILING 2.0
#define ID_WALL 3.0
#define ID_PILLAR 4.0
#define ID_CHAIN 5.0
#define ID_LANTERN_FRAME 6.0
#define ID_LANTERN_CORE 7.0
#define ID_MIRROR 8.0

// -------------------------------------------------------------------------
// MATH & UTILS
// -------------------------------------------------------------------------

float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

mat2 rot(float a) {
    float s = sin(a);
    float c = cos(a);
    return mat2(c, -s, s, c);
}

vec2 getPath(float z) {
    return vec2(sin(z * 0.1) * 4.0, 0.0);
}

// -------------------------------------------------------------------------
// SDF PRIMITIVES
// -------------------------------------------------------------------------

float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sdHexPrism(vec3 p, vec2 h) {
    const vec3 k = vec3(-0.8660254, 0.5, 0.57735);
    p = abs(p);
    p.xz -= 2.0*min(dot(k.xy, p.xz), 0.0)*k.xy;
    vec2 d = vec2(
       length(p.xz - vec2(clamp(p.x, -k.z*h.x, k.z*h.x), h.x))*sign(p.z - h.x),
       p.y-h.y );
    return min(max(d.x,d.y),0.0) + length(max(d,0.0));
}

float sdHex(vec2 p, float r) {
    const vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
    p = abs(p);
    p -= 2.0*min(dot(k.xy, p), 0.0)*k.xy;
    p -= vec2(clamp(p.x, -k.z*r, k.z*r), r);
    return length(p)*sign(p.y);
}

float sdLink(vec3 p, float le, float r1, float r2) {
    vec3 q = vec3(p.x, max(abs(p.y) - le, 0.0), p.z);
    return length(vec2(length(q.xy) - r1, q.z)) - r2;
}

float sdTorus(vec3 p, vec2 t) {
    vec2 q = vec2(length(p.xz)-t.x,p.y);
    return length(q)-t.y;
}

float sdCappedCylinder(vec3 p, float h, float r) {
  vec2 d = abs(vec2(length(p.xz),p.y)) - vec2(r,h);
  return min(max(d.x,d.y),0.0) + length(max(d,0.0));
}

// -------------------------------------------------------------------------
// PHYSICS SIMULATION HELPER
// -------------------------------------------------------------------------
vec2 getLanternAngles(float lanternIndex, float time) {
    float rndPhase = hash(lanternIndex * 13.0 + 41.0);
    float rndSpeed = 0.8 + 0.4 * hash(lanternIndex * 7.0 + 99.0);
    float rndAmp = 0.8 + 0.4 * hash(lanternIndex * 23.0 + 5.0);

    float t = time * 2.0 * rndSpeed + rndPhase * 100.0;

    float a1 = sin(t) * 0.2 * rndAmp;
    float a2 = sin(t - 0.8) * 0.25 * rndAmp;

    return vec2(a1, a2);
}

// -------------------------------------------------------------------------
// SCENE MAPPING
// -------------------------------------------------------------------------

// --- [ADDED] MAP STATIC: Calculates only static geometry for shadows ---
float mapStatic(vec3 p) {
    vec2 pathOffset = getPath(p.z);
    p.x -= pathOffset.x; // Apply Bending

    float dWall = 2.5 - abs(p.x);
    float dFloor = p.y - (-1.5);

    float baseCeilH = 3.8 - 0.2 * p.x * p.x;
    float zRepeat = 6.0;
    float zRibDist = abs(mod(p.z, zRepeat) - 3.0);
    float ribH = smoothstep(0.3, 0.2, zRibDist) * 0.15;
    float spineH = smoothstep(0.3, 0.2, abs(p.x)) * 0.12;
    float finalCeilH = baseCeilH - max(ribH, spineH);
    float dCeil = finalCeilH - p.y;

    float zLocal = mod(p.z, zRepeat) - zRepeat * 0.5;
    vec3 pPillar = vec3(abs(p.x) - 2.5, p.y, zLocal);
    float dPillar = length(pPillar.xz) - 0.55;

    float d = dFloor;
    if(dCeil < d) d = dCeil;
    if(dWall < d) d = dWall;
    if(dPillar < d) d = dPillar;

    return d;
}

// --- MAIN MAP: Includes everything ---
vec2 map(vec3 p) {
    vec2 pathOffset = getPath(p.z);
    vec3 pGlobal = p;

    // BEND WORLD (Applied to p for all subsequent logic)
    p.x -= pathOffset.x;

    // Static Geometry
    float dWall = 2.5 - abs(p.x);
    float dFloor = p.y - (-1.5);

    float baseCeilH = 3.8 - 0.2 * p.x * p.x;
    float zRepeat = 6.0;
    float zRibDist = abs(mod(p.z, zRepeat) - 3.0);
    float ribH = smoothstep(0.3, 0.2, zRibDist) * 0.15;
    float spineH = smoothstep(0.3, 0.2, abs(p.x)) * 0.12;
    float finalCeilH = baseCeilH - max(ribH, spineH);
    float dCeil = finalCeilH - p.y;

    float zLocal = mod(p.z, zRepeat) - zRepeat * 0.5;
    vec3 pPillar = vec3(abs(p.x) - 2.5, p.y, zLocal);
    float dPillar = length(pPillar.xz) - 0.55;

    float d = dFloor;
    float id = ID_FLOOR;

    if(dCeil < d) { d = dCeil; id = ID_CEILING; }
    if(dWall < d) { d = dWall; id = ID_WALL; }
    if(dPillar < d) { d = dPillar; id = ID_PILLAR; }

    // --- DECORATION LOGIC ---
    float lSpacing = 12.0;
    float lIndex = floor((pGlobal.z + lSpacing*0.5) / lSpacing);
    float lCenterZ = lIndex * lSpacing;

    vec2 lPath = getPath(lCenterZ);
    // Use bent 'p' for X positioning relative to wall
    vec3 pDecor = p;
    // Use unbent global Z for spacing logic
    pDecor.z = pGlobal.z - lCenterZ;

    float sideSignL = (pDecor.x > 0.0) ? 1.0 : -1.0;

    vec3 pMountL = pDecor;
    pMountL.x -= sideSignL * 2.5;
    pMountL.y -= 1.0;

    float dLanternMetal = MAX_DIST;
    float dLanternCore = MAX_DIST;

    // Lanterns
    {
        vec3 pBracket = pMountL;
        pBracket.x *= -sideSignL;
        float dBracket = sdBox(pBracket - vec3(0.2, 0.0, 0.0), vec3(0.2, 0.05, 0.05));

        float uniqueID = lIndex + (sideSignL * 0.1);
        vec2 angles = getLanternAngles(uniqueID, iTime);

        vec3 pChainSys = pBracket;
        pChainSys -= vec3(0.35, 0.0, 0.0);
        pChainSys.xy *= rot(angles.x);

        float dChain = MAX_DIST;
        float linkSpacing = 0.14;
        vec3 pL1 = pChainSys; vec3 pL1r = pL1; pL1r.xz *= rot(PI/2.0);
        dChain = min(dChain, sdLink(pL1r - vec3(0.0, -0.06, 0.0), 0.03, 0.025, 0.008));
        vec3 pL2 = pChainSys;
        dChain = min(dChain, sdLink(pL2 - vec3(0.0, -0.06 - linkSpacing, 0.0), 0.03, 0.025, 0.008));
        vec3 pL3 = pChainSys; vec3 pL3r = pL3; pL3r.xz *= rot(PI/2.0);
        dChain = min(dChain, sdLink(pL3r - vec3(0.0, -0.06 - linkSpacing*2.0, 0.0), 0.03, 0.025, 0.008));

        float chainLengthStrut = 0.06 + linkSpacing*2.0 + 0.06;
        vec3 pL = pChainSys;
        pL.y += chainLengthStrut;
        pL.xy *= rot(angles.y);

        float dTopRing = sdTorus(pL.xzy, vec2(0.03, 0.008));
        float roofH = 0.15;
        vec3 pRoof = pL; pRoof.y += roofH * 0.5;
        float tRoof = clamp(-pL.y / roofH, 0.0, 1.0);
        float roofW = mix(0.04, 0.16, tRoof);
        float dRoof = sdHex(pL.xz, roofW);
        vec2 wRoof = vec2(dRoof, abs(pL.y + roofH*0.5) - roofH*0.5);
        float dRoof3D = min(max(wRoof.x, wRoof.y), 0.0) + length(max(wRoof, 0.0));

        float cageH = 0.25;
        vec3 pCage = pL; pCage.y += roofH + cageH * 0.5;

        dLanternCore = sdHexPrism(pCage, vec2(0.12, cageH * 0.5));

        vec3 pBars = pCage;
        float angle = atan(pBars.z, pBars.x);
        float radius = length(pBars.xz);
        float sector = PI / 3.0;
        float aLocal = mod(angle + sector * 0.5, sector) - sector * 0.5;
        vec2 barPos = vec2(radius * cos(aLocal), radius * sin(aLocal));
        barPos.x -= 0.145;
        float dFrameBars = length(barPos) - 0.015;
        dFrameBars = max(dFrameBars, abs(pBars.y) - (cageH * 0.5 + 0.02));

        vec3 pBase = pL; pBase.y += roofH + cageH + 0.01;
        float dBase = sdHexPrism(pBase, vec2(0.15, 0.01));

        float dLanternFrameAll = min(dTopRing, min(dRoof3D, min(dBase, dFrameBars)));
        float dInnerCut = sdHexPrism(pCage, vec2(0.115, cageH * 0.48));
        dLanternFrameAll = max(dLanternFrameAll, -dInnerCut);

        dLanternMetal = min(dBracket, min(dChain, dLanternFrameAll));
    }

    // --- MIRRORS ---
    float mIndex = floor(((pGlobal.z + 6.0) + lSpacing*0.5) / lSpacing);
    float mCenterZ = mIndex * lSpacing - 6.0;

    vec3 pMir = p; // Uses bent p
    pMir.z = pGlobal.z - mCenterZ;

    float dMirror = MAX_DIST;
    {
        pMir.y -= 0.0; // Eye Level

        float wallDist = abs(pMir.x) - 2.5;
        pMir.x = wallDist + 0.15;

        vec3 pBody = pMir;
        float d2D = length(pBody.yz * vec2(0.5, 0.8)) - 0.4;
        vec2 w = vec2(d2D, abs(pBody.x) - 0.01);
        float dMirBody = min(max(w.x, w.y), 0.0) + length(max(w, 0.0));

        vec3 pFrame = pMir;
        float dFrame2D = length(pFrame.yz * vec2(0.5, 0.8)) - 0.4;
        float dMirrorFrame = length(vec2(dFrame2D, pFrame.x)) - 0.03;

        dLanternMetal = min(dLanternMetal, dMirrorFrame);
        dMirror = dMirBody;
    }

    if(dLanternMetal < d) { d = dLanternMetal; id = ID_CHAIN; }
    if(dLanternCore < d) { d = dLanternCore; id = ID_LANTERN_CORE; }
    if(dMirror < d) { d = dMirror; id = ID_MIRROR; }

    return vec2(d, id);
}

// -------------------------------------------------------------------------
// RAYMARCHING
// -------------------------------------------------------------------------

vec2 rayMarch(vec3 ro, vec3 rd, int maxSteps) {
    float dO = 0.0;
    float matId = ID_NONE;

    for(int i = 0; i < MAX_STEPS; i++) {
        if(i >= maxSteps) break;

        vec3 p = ro + rd * dO;
        vec2 dS = map(p);

        if(abs(dS.x) < SURF_DIST) {
            dO += dS.x;
            matId = dS.y;
            break;
        }

        dO += dS.x;
        if(dO > MAX_DIST) break;
    }
    return vec2(dO, matId);
}

// --- [ADDED] SOFT SHADOW FUNCTION ---
// Uses mapStatic() instead of map() to ignore Lanterns
float softShadow(vec3 ro, vec3 rd, float mint, float maxt, float k) {
    float res = 1.0;
    float t = mint;
    for(int i = 0; i < 32; i++) {
        float h = mapStatic(ro + rd * t); // Query STATIC only
        res = min(res, k * h / t);
        t += h;
        if(res < 0.001 || t > maxt) break;
    }
    return clamp(res, 0.0, 1.0);
}

vec3 getNormal(vec3 p) {
    float d = map(p).x;
    vec2 e = vec2(0.001, 0.0);
    vec3 n = d - vec3(
        map(p - e.xyy).x,
        map(p - e.yxy).x,
        map(p - e.yyx).x
    );
    return normalize(n);
}

// -------------------------------------------------------------------------
// PATTERNS
// -------------------------------------------------------------------------

float sdRupeeExact(vec2 p, float w, float h, float s) {
    p = abs(p);
    if (p.y < s) return p.x - w;
    vec2 corner = vec2(w, s);
    vec2 tip = vec2(0.0, h);
    vec2 edge = tip - corner;
    vec2 normal = normalize(vec2(edge.y, -edge.x));
    return dot(p, normal) - dot(tip, normal);
}

float getFloorPattern(vec3 p) {
    vec2 uv = vec2(p.x - getPath(p.z).x, p.z);

    float rW = 0.28;
    float capHeight = 0.27;
    float bodyHalfHeight = 0.70;
    float rS = bodyHalfHeight;
    float rH = bodyHalfHeight + capHeight;

    float gap = 0.08;
    float gridX = rW * 2.0 + gap;
    float gridY = rH + rS + gap;

    vec2 p1 = mod(uv, vec2(gridX, gridY * 2.0)) - vec2(gridX * 0.5, gridY);
    vec2 p2 = mod(uv + vec2(gridX * 0.5, gridY), vec2(gridX, gridY * 2.0)) - vec2(gridX * 0.5, gridY);

    float d = min(sdRupeeExact(p1, rW, rH, rS), sdRupeeExact(p2, rW, rH, rS));
    return smoothstep(0.01, -0.01, d);
}

float getWallTexture(vec3 p) {
    vec2 uv = p.yz;
    float scale = 2.5;
    uv *= scale;
    vec2 id = floor(uv);
    vec2 gridUV = fract(uv);
    float rowOffset = mod(id.y, 2.0) * 0.5;
    id.x = floor(uv.x + rowOffset);
    gridUV.x = fract(uv.x + rowOffset);
    float tileRand = hash2(id);
    float tileVal = 0.4 + 0.6 * tileRand;
    vec2 edgeDist = min(gridUV, 1.0 - gridUV);
    float mortar = smoothstep(0.0, 0.12, min(edgeDist.x, edgeDist.y));
    float noise = hash2(uv * 2.0);
    noise = 0.8 + 0.2 * noise;
    return tileVal * mortar * noise;
}

float getPillarTexture(vec3 p) {
    float zRepeat = 6.0;
    float localZ = mod(p.z, zRepeat) - zRepeat * 0.5;
    float localX = abs(p.x) - 2.5;
    float angle = atan(localZ, localX);
    float radius = 0.55;
    vec2 uv = vec2(angle * radius, p.y);
    uv.x *= 25.0;
    uv.y *= 1.5;
    vec2 id = floor(uv);
    vec2 gridUV = fract(uv);
    float rowOffset = mod(id.y, 2.0) * 0.5;
    id.x = floor(uv.x + rowOffset);
    gridUV.x = fract(uv.x + rowOffset);
    float tileRand = hash2(id);
    float tileVal = 0.4 + 0.6 * tileRand;
    vec2 edgeDist = min(gridUV, 1.0 - gridUV);
    float mortar = smoothstep(0.0, 0.05, min(edgeDist.x, edgeDist.y));
    float noise = hash2(uv * 3.0);
    noise = 0.8 + 0.2 * noise;
    return tileVal * mortar * noise;
}

// -------------------------------------------------------------------------
// LIGHTING SYSTEM
// -------------------------------------------------------------------------

vec3 getMovingLightPos(float lCenterZ, float sideSign) {
    vec2 lPath = getPath(lCenterZ);
    vec3 p = vec3(lPath.x + sideSign * 2.5, 1.0, lCenterZ);
    p.x -= sideSign * 0.50;

    float lIndex = floor((lCenterZ + 6.0) / 12.0);

    float uniqueID = lIndex + (sideSign * 0.1);
    vec2 angles = getLanternAngles(uniqueID, iTime);

    vec2 arm1 = vec2(0.0, -0.40);
    arm1 *= rot(-angles.x * sideSign);

    vec2 arm2 = vec2(0.0, -0.275);
    arm2 *= rot(-(angles.x + angles.y) * sideSign);

    p.xy += arm1; p.xy += arm2;
    return p;
}

vec3 getLighting(vec3 p, vec3 n, vec3 rd, float id) {
    if(id == ID_LANTERN_CORE) {
        return vec3(0.4, 0.05, 0.8) * 6.0;
    }
    if(id == ID_CHAIN || id == ID_LANTERN_FRAME) return vec3(0.005);

    float matSpec = 0.5;
    vec3 col = vec3(0.0);
    float tileMask = 0.0;
    float texVal = 1.0;

    if(id == ID_FLOOR) {
        tileMask = getFloorPattern(p);
        col = mix(vec3(0.0), vec3(0.01, 0.01, 0.02), tileMask);
        matSpec = 1.0;
    }
    else if (id == ID_CEILING) {
        col = vec3(0.002, 0.001, 0.002);
        col += vec3(0.005) * clamp(-n.y, 0.0, 1.0);
        matSpec = 0.02;
    }
    else if (id == ID_WALL) {
        texVal = getWallTexture(p);
        col = vec3(0.06, 0.05, 0.07) * texVal;
        matSpec = 0.05 * texVal;
    }
    else if (id == ID_PILLAR) {
        texVal = getPillarTexture(p);
        col = vec3(0.06, 0.05, 0.07) * texVal;
        matSpec = 0.1 * texVal;
    }
    else if (id == ID_MIRROR) {
        col = vec3(0.01);
        matSpec = 4.0;
    }

    vec3 totalLight = vec3(0.0);
    vec3 totalSpec = vec3(0.0);

    float lightSpacing = 12.0;
    float currentIdx = floor((p.z + lightSpacing*0.5) / lightSpacing);

    for(float i = -1.0; i <= 1.0; i++) {
        float idx = currentIdx + i;
        float lZ = idx * lightSpacing;

        for(int side = 0; side < 2; side++) {
            float sideSign = (side == 0) ? -1.0 : 1.0;

            vec3 lPos = getMovingLightPos(lZ, sideSign);
            vec3 lDir = lPos - p;
            float dist = length(lDir);
            lDir = normalize(lDir);

            // --- [ADDED] SHADOW CALCULATION ---
            float shadow = 1.0;
            if (dist < 20.0) {
                // Use softShadow with k=8.0 and mapStatic to avoid lantern self-shadows
                shadow = softShadow(p, lDir, 0.05, dist, 8.0);
            }

            float att = 1.0 / (1.0 + dist * 0.5 + dist * dist * 1.0);

            if(att > 0.001) {
                float diff = max(dot(n, lDir), 0.0);

                vec3 ref = reflect(-lDir, n);
                float specPow = (id == ID_MIRROR) ? 128.0 : 16.0;
                float spec = pow(max(dot(ref, -rd), 0.0), specPow);

                vec3 lightColor = vec3(0.35, 0.05, 0.7) * 2.5;

                // Shadow multiplies light contribution
                totalLight += lightColor * diff * att * shadow;
                totalSpec += lightColor * spec * att * matSpec * shadow;
            }
        }
    }

    if(id == ID_CHAIN || id == ID_LANTERN_FRAME) {
        totalSpec *= 0.2;
    }

    if(id == ID_FLOOR) totalSpec *= tileMask;

    vec3 linearColor = col * totalLight + totalSpec;

    return linearColor;
}

// -------------------------------------------------------------------------
// MAIN
// -------------------------------------------------------------------------

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;

    float speed = 2.5;
    float zPos = -(iTime * speed);

    vec3 ro = vec3(getPath(zPos).x, 0.0, zPos);
    float lookAhead = 2.0;
    vec3 target = vec3(getPath(zPos - lookAhead).x, 0.0, zPos - lookAhead);

    vec3 fwd = normalize(target - ro);
    vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
    vec3 up = cross(fwd, right);
    vec3 rd = normalize(fwd + uv.x * right + uv.y * up);

    vec2 result = rayMarch(ro, rd, MAX_STEPS);
    float d = result.x;
    float id = result.y;

    vec3 col = vec3(0.0);

    if(d < MAX_DIST) {
        vec3 p = ro + rd * d;
        vec3 n = getNormal(p);

        col = getLighting(p, n, rd, id);

        bool isReflective = (id == ID_FLOOR) || (id == ID_MIRROR);
        float brightness = length(col);

        if(isReflective && (brightness > 0.01 || id == ID_MIRROR)) {
            vec3 rRd = reflect(rd, n);
            vec3 rRo = p + n * SURF_DIST * 4.0;
            vec2 rRes = rayMarch(rRo, rRd, REFLECTION_STEPS);
            float rD = rRes.x;
            float rId = rRes.y;

            if(rD < MAX_DIST) {
                vec3 rP = rRo + rRd * rD;
                vec3 rN = getNormal(rP);
                vec3 rCol = getLighting(rP, rN, rRd, rId);

                float fresnel = 0.0;

                if(id == ID_FLOOR) {
                    float tileMask = getFloorPattern(p);
                    fresnel = 0.4 + 0.6 * pow(1.0 - max(dot(-rd, n), 0.0), 5.0);
                    col = mix(col, rCol * 2.0, fresnel * tileMask);
                } else if (id == ID_MIRROR) {
                    fresnel = 0.9 + 0.1 * pow(1.0 - max(dot(-rd, n), 0.0), 5.0);
                    col = mix(col, rCol, fresnel);
                }
            }
        }
    }

    col = pow(col, vec3(0.4545));
    col = max(col, vec3(0.0));

    fragColor = vec4(col, 1.0);
}

void main() {
    mainImage(gl_FragColor, gl_FragCoord.xy);
}
