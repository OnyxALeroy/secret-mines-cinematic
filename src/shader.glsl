#ifdef GL_ES
precision highp float;
#endif

uniform vec3 iResolution;
uniform float iTime;

// --- SPACE WARPING ---
vec3 curve(vec3 p) {
    float offset = sin(p.z * 0.15) * 4.0;
    p.x += offset;
    return p;
}

// 1. GEOMETRY
float map(vec3 p) {
    p = curve(p);

    float floorDist = p.y;
    float walls = -max(abs(p.x) - 2.5, p.y - 3.5);
    float arch = length(vec2(p.x, max(0.0, p.y - 2.5))) - 2.0;

    // Wall torches
    float torchZ = mod(p.z + 2.0, 4.0) - 2.0;
    float leftTorch = length(vec3(p.x + 2.5, p.y - 1.5, torchZ)) - 0.12;
    float rightTorch = length(vec3(p.x - 2.5, p.y - 1.5, torchZ)) - 0.12;
    float torches = min(leftTorch, rightTorch);

    float scene = min(floorDist, max(walls, -arch));
    return min(scene, torches);
}

vec3 getNormal(vec3 p) {
    vec2 e = vec2(0.001, 0.0);
    return normalize(vec3(
            map(p + e.xyy) - map(p - e.xyy),
            map(p + e.yxy) - map(p - e.yxy),
            map(p + e.yyx) - map(p - e.yyx)
        ));
}

vec3 torchLighting(vec3 p, vec3 n, vec3 rd, vec3 lPos, vec3 lCol, float intensity) {
    vec3 lDir = normalize(lPos - p);
    float d = length(lPos - p);
    float atten = 1.0 / (d * d + 0.8);
    float diff = max(dot(n, lDir), 0.0);
    float spec = pow(max(dot(reflect(lDir, n), rd), 0.0), 32.0);
    return lCol * (diff + spec) * atten * intensity;
}

// --- VOLUMETRIC FOG ---
vec3 getVolumetricFog(vec3 ro, vec3 rd, float t) {
    vec3 fog = vec3(0.0);
    float camZ = ro.z;
    int startIdx = int(floor((camZ) / 4.0));

    for (int i = -2; i < 5; i++) {
        float lZ = float(startIdx + i) * 4.0;
        float curveOffset = sin(lZ * 0.15) * 4.0;

        vec3 lpL = vec3(-curveOffset - 2.5, 1.5, lZ);
        vec3 lpR = vec3(-curveOffset + 2.5, 1.5, lZ);
        vec3 lCol = vec3(0.5, 0.2, 0.8) * 0.9;

        vec3 vL = lpL - ro;
        float hL = clamp(dot(vL, rd), 0.0, t);
        float distL = length(vL - rd * hL);

        vec3 vR = lpR - ro;
        float hR = clamp(dot(vR, rd), 0.0, t);
        float distR = length(vR - rd * hR);

        fog += lCol * (0.015 / (distL * distL + 0.02));
        fog += lCol * (0.015 / (distR * distR + 0.02));
    }
    return fog;
}

vec3 getSceneColor(vec3 p, vec3 n, vec3 rd, float t) {
    vec3 cp = curve(p);
    float lZ = floor((p.z + 2.0) / 4.0) * 4.0;
    float curveOffset = sin(lZ * 0.15) * 4.0;

    vec3 lpL = vec3(-curveOffset - 2.5, 1.5, lZ);
    vec3 lpR = vec3(-curveOffset + 2.5, 1.5, lZ);
    vec3 lCol = vec3(0.5, 0.2, 0.8);

    vec3 col = vec3(0.0);
    float torchZRel = mod(p.z + 2.0, 4.0) - 2.0;
    float distToTorch = min(length(vec3(cp.x + 2.5, cp.y - 1.5, torchZRel)),
            length(vec3(cp.x - 2.5, cp.y - 1.5, torchZRel)));

    if (distToTorch < 0.15) {
        float viewAngle = max(dot(n, -rd), 0.0);
        vec3 coreColor = vec3(1.0, 0.9, 0.8) * pow(viewAngle, 4.0) * 5.0;
        float fresnel = pow(1.0 - viewAngle, 3.0);
        vec3 rimColor = lCol * fresnel * 8.0;
        return coreColor + rimColor;
    } else if (cp.y < 0.01) {
        // --- TILE COLOR LOGIC (Diffuse) ---
        vec2 scale = cp.xz * 2.0;
        vec2 grid = floor(scale);
        vec2 sub = fract(scale) - 0.5;

        float check = mod(grid.x + grid.y, 2.0);

        // Increased brightness/contrast for visibility
        vec3 tCol1 = vec3(0.15, 0.05, 0.2); // Visible Purple
        vec3 tCol2 = vec3(0.04, 0.04, 0.06); // Dark Gray
        vec3 tileColor = (check > 0.5) ? tCol1 : tCol2;

        // Dark Matte Grout
        float edge = max(abs(sub.x), abs(sub.y));
        float border = smoothstep(0.45, 0.48, edge);

        col = mix(tileColor, vec3(0.02), border);
    } else {
        col = vec3(0.05, 0.04, 0.06);
    }

    col += torchLighting(p, n, rd, lpL, lCol, 5.0);
    col += torchLighting(p, n, rd, lpR, lCol, 5.0);

    return col * exp(-0.04 * t);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;

    float time = iTime * 4.0;
    vec3 ro = vec3(0.0, 1.2, time);
    ro.x -= sin(ro.z * 0.15) * 4.0;

    vec3 lookAt = vec3(0.0, 1.2, time + 2.0);
    lookAt.x -= sin(lookAt.z * 0.15) * 4.0;

    vec3 fwd = normalize(lookAt - ro);
    vec3 right = normalize(cross(vec3(0, 1, 0), fwd));
    vec3 up = cross(fwd, right);
    vec3 rd = normalize(fwd + uv.x * right + uv.y * up);

    float t = 0.0;
    for (int i = 0; i < 100; i++) {
        float d = map(ro + rd * t);
        if (d < 0.001 || t > 60.0) break;
        t += d;
    }

    vec3 col = vec3(0.01, 0.0, 0.02);
    vec3 fog = vec3(0.0);

    if (t < 60.0) {
        vec3 p = ro + rd * t;
        vec3 n = getNormal(p);

        fog = getVolumetricFog(ro, rd, t);

        if (curve(p).y < 0.01) {
            // Re-calculate tile math to separate reflective tile vs matte grout
            vec3 cp = curve(p);
            vec2 scale = cp.xz * 2.0;
            vec2 grid = floor(scale);
            vec2 sub = fract(scale) - 0.5;
            float check = mod(grid.x + grid.y, 2.0);

            vec3 tCol1 = vec3(0.15, 0.05, 0.2);
            vec3 tCol2 = vec3(0.04, 0.04, 0.06);
            vec3 tileBase = (check > 0.5) ? tCol1 : tCol2;

            // Calculate Grout Border
            float edge = max(abs(sub.x), abs(sub.y));
            float border = smoothstep(0.45, 0.48, edge);

            // Grout color is dark and matte
            vec3 groutColor = vec3(0.02);
            vec3 finalSurfaceColor = mix(tileBase, groutColor, border);

            // --- REFLECTION LOGIC ---
            vec3 flatNormal = vec3(0.0, 1.0, 0.0);
            vec3 refDir = reflect(rd, flatNormal);
            vec3 refRo = p + flatNormal * 0.01;

            vec3 reflectedCol = vec3(0.0);

            // Only raymarch reflection if we are NOT on the grout (optimization)
            if (border < 0.9) {
                float rt = 0.0;
                for (int j = 0; j < 60; j++) {
                    float rd_dist = map(refRo + refDir * rt);
                    if (rd_dist < 0.001 || rt > 40.0) break;
                    rt += rd_dist;
                }
                if (rt < 40.0) {
                    vec3 rp = refRo + refDir * rt;
                    reflectedCol = getSceneColor(rp, getNormal(rp), refDir, rt);
                    reflectedCol += getVolumetricFog(refRo, refDir, rt);
                }
            }

            // --- THE MIX ---
            // "reflectivity" drops to 0.0 where "border" is 1.0 (the grout)
            float reflectivity = (1.0 - border) * 0.6;

            col = mix(finalSurfaceColor, reflectedCol, reflectivity);
        } else {
            col = getSceneColor(p, n, rd, t);
        }
    }

    col += fog;

    fragColor = vec4(col, 1.0);
}

void main() {
    mainImage(gl_FragColor, gl_FragCoord.xy);
}
