// Avatar SVG chibi dùng độc lập trong web; chỉ truyền các lựa chọn đã kiểm soát.
function generateAvatarSvg(name, playerConfig) {
  const skin = (playerConfig && playerConfig.skinColor) || '#FDE2D0';
  const hair = (playerConfig && playerConfig.hairColor) || '#1E293B';
  const acc = (playerConfig && playerConfig.accessory) || 'none';
  const hairStyle = (playerConfig && playerConfig.hairStyle) || 'messy';
  const cloth = (playerConfig && playerConfig.clothingColor) || '#1E293B';

  // ID an toàn cho SVG gradient
  const uid = 'av_' + Math.abs((name || 'u').split('').reduce((acc, c) => ((acc << 5) - acc) + c.charCodeAt(0), 0)).toString(36);

  // PHỤ KIỆN TINH TẾ, DỄ THƯƠNG
  let accSvg = '';
  if (acc === 'straw_hat') {
    accSvg = `
      <g class="acc-straw-hat">
        <!-- Chóp nón vòm tròn mềm mại -->
        <path d="M 32 18 C 32 8 41 5 50 5 C 59 5 68 8 68 18 Z" fill="#FDE047" stroke="#CA8A04" stroke-width="1.2" />
        <ellipse cx="50" cy="18" rx="18" ry="4" fill="#FACC15" />
        <!-- Dải ruy băng đỏ thắm tinh tế -->
        <path d="M 32 17.5 Q 50 20.5 68 17.5 L 68 20 Q 50 23 32 20 Z" fill="#E11D48" />
        <!-- Vành nón rộng thanh thoát uốn cong tự nhiên -->
        <ellipse cx="50" cy="21.5" rx="35" ry="8" fill="#FACC15" stroke="#CA8A04" stroke-width="1.3" />
        <ellipse cx="50" cy="22" rx="33" ry="6" fill="none" stroke="#EAB308" stroke-width="0.8" stroke-dasharray="2,2" />
        <!-- Đuôi nơ ruy băng nhẹ nhàng -->
        <path d="M 64 20 Q 70 24 73 29 M 66 21 Q 69 26 67 31" fill="none" stroke="#E11D48" stroke-width="1.8" stroke-linecap="round" />
      </g>
    `;
  } else if (acc === 'cat_ears') {
    accSvg = `
      <g class="acc-cat-ears">
        <!-- Tai trái -->
        <path d="M 24 28 C 22 17 22 10 32 11 C 36 12 37 19 37 24 Z" fill="#334155" />
        <path d="M 26 25 C 25 18 25 14 31 15 C 34 16 35 20 35 23 Z" fill="#FBCFE8" />
        <circle cx="30" cy="20" r="1.5" fill="#FFFFFF" opacity="0.8" />
        <!-- Tai phải -->
        <path d="M 76 28 C 78 17 78 10 68 11 C 64 12 63 19 63 24 Z" fill="#334155" />
        <path d="M 74 25 C 75 18 75 14 69 15 C 66 16 65 20 65 23 Z" fill="#FBCFE8" />
        <circle cx="70" cy="20" r="1.5" fill="#FFFFFF" opacity="0.8" />
      </g>
    `;
  } else if (acc === 'witch_hat') {
    accSvg = `
      <g class="acc-witch-hat">
        <!-- Vành nón cong uyển chuyển -->
        <ellipse cx="50" cy="20.5" rx="35" ry="7.5" fill="#312E81" />
        <ellipse cx="50" cy="20.5" rx="33" ry="5.5" fill="#3730A3" />
        <!-- Thân nón uốn cong tinh nghịch -->
        <path d="M 32 20 C 35 12 43 4 56 2 C 62 1 67 3 63 7 C 58 11 56 16 68 20 Z" fill="#1E1B4B" />
        <!-- Đai tím thắt lưng & khóa vàng -->
        <path d="M 33 19 Q 50 22 67 19 L 68 21.5 Q 50 24.5 32 21.5 Z" fill="#7C3AED" />
        <rect x="46" y="18" width="8" height="5" rx="1.5" fill="#FBBF24" />
        <rect x="48" y="19" width="4" height="3" rx="0.8" fill="#1E1B4B" />
        <!-- Ngôi sao vàng nhỏ lấp lánh -->
        <polygon points="58,6 59,8 61,8.5 59.5,10 60,12 58.5,11 57,12 57.5,10 56,8.5 58,8" fill="#FEF08A" opacity="0.9" />
      </g>
    `;
  } else if (acc === 'horns') {
    accSvg = `
      <g class="acc-devil-horns">
        <path d="M 32 23 C 27 15 21 6 27 2 C 32 8 36 15 37 21 Z" fill="#EF4444" />
        <path d="M 31 20 C 28 14 24 9 27 4" fill="none" stroke="#FCA5A5" stroke-width="1.4" stroke-linecap="round" />
        <path d="M 68 23 C 73 15 79 6 73 2 C 68 8 64 15 63 21 Z" fill="#EF4444" />
        <path d="M 69 20 C 72 14 76 9 73 4" fill="none" stroke="#FCA5A5" stroke-width="1.4" stroke-linecap="round" />
      </g>
    `;
  } else if (acc === 'sunglasses') {
    accSvg = `
      <g class="acc-sunglasses">
        <rect x="30" y="38" width="17" height="11" rx="4.5" fill="#0F172A" stroke="#334155" stroke-width="1.6" />
        <rect x="53" y="38" width="17" height="11" rx="4.5" fill="#0F172A" stroke="#334155" stroke-width="1.6" />
        <line x1="47" y1="42" x2="53" y2="42" stroke="#475569" stroke-width="2" />
        <!-- Vệt phản chiếu sành điệu -->
        <line x1="33" y1="46" x2="41" y2="39" stroke="rgba(255,255,255,0.45)" stroke-width="1.5" stroke-linecap="round" />
        <line x1="56" y1="46" x2="64" y2="39" stroke="rgba(255,255,255,0.45)" stroke-width="1.5" stroke-linecap="round" />
      </g>
    `;
  } else if (acc === 'halo') {
    accSvg = `
      <g class="acc-angel-halo">
        <ellipse cx="50" cy="8" rx="23" ry="5.5" fill="none" stroke="#FEF08A" stroke-width="4.5" opacity="0.35" />
        <ellipse cx="50" cy="8" rx="23" ry="5.5" fill="none" stroke="#FACC15" stroke-width="2.5" />
        <circle cx="69" cy="6" r="1.5" fill="#FFFFFF" />
        <circle cx="31" cy="10" r="1.2" fill="#FFFFFF" />
      </g>
    `;
  } else if (acc === 'flower_crown') {
    accSvg = `
      <g class="acc-flower-crown">
        <path d="M 27 26 Q 50 17 73 26" fill="none" stroke="#16A34A" stroke-width="2" stroke-linecap="round" />
        <circle cx="32" cy="23.5" r="3" fill="#F43F5E" /><circle cx="32" cy="23.5" r="1.2" fill="#FEF08A" />
        <circle cx="41" cy="20.5" r="3.2" fill="#38BDF8" /><circle cx="41" cy="20.5" r="1.2" fill="#FFFFFF" />
        <circle cx="50" cy="18.5" r="3.8" fill="#FBBF24" /><circle cx="50" cy="18.5" r="1.5" fill="#EA580C" />
        <circle cx="59" cy="20.5" r="3.2" fill="#C084FC" /><circle cx="59" cy="20.5" r="1.2" fill="#FFFFFF" />
        <circle cx="68" cy="23.5" r="3" fill="#F43F5E" /><circle cx="68" cy="23.5" r="1.2" fill="#FEF08A" />
        <path d="M 36.5 21 Q 38 18 40 20" fill="none" stroke="#22C55E" stroke-width="1.5" />
        <path d="M 63.5 21 Q 65 18 67 20" fill="none" stroke="#22C55E" stroke-width="1.5" />
      </g>
    `;
  }

  // 6 KIỂU TÓC MỀM MẠI, NÉT VẼ TỰ NHIÊN, BỒNG BỀNH
  let hairSvg = '';
  if (hairStyle === 'spiky') {
    // Tóc vuốt lãng tử anime
    hairSvg = `
      <g class="hair-spiky">
        <path d="M 23 44 C 18 30 25 15 50 15 C 75 15 82 30 77 44 C 74 36 71 30 65 34 C 60 25 50 22 40 26 C 30 28 25 36 23 44 Z" fill="${hair}" />
        <path d="M 36 17 Q 41 8 46 15 Q 50 7 54 15 Q 60 9 64 18" fill="none" stroke="${hair}" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round" />
        <path d="M 24 38 Q 28 28 34 32 Q 38 24 43 33 Q 48 23 53 32 Q 58 25 63 34 Q 69 29 74 39 Q 71 31 66 23 Q 50 14 34 23 Q 27 30 24 38 Z" fill="${hair}" />
        <path d="M 33 22 Q 50 16 67 22" fill="none" stroke="rgba(255,255,255,0.28)" stroke-width="2" stroke-linecap="round" />
      </g>
    `;
  } else if (hairStyle === 'curly') {
    // Tóc xoăn bồng bềnh
    hairSvg = `
      <g class="hair-curly">
        <path d="M 24 46 C 18 40 18 28 26 22 C 28 14 40 12 50 12 C 60 12 72 14 74 22 C 82 28 82 40 76 46 C 79 40 78 30 72 26 C 66 18 54 18 50 20 C 46 18 34 18 28 26 C 22 30 21 40 24 46 Z" fill="${hair}" />
        <circle cx="23" cy="35" r="5.5" fill="${hair}" /><circle cx="22" cy="43" r="5" fill="${hair}" />
        <circle cx="77" cy="35" r="5.5" fill="${hair}" /><circle cx="78" cy="43" r="5" fill="${hair}" />
        <circle cx="31" cy="18" r="6" fill="${hair}" /><circle cx="43" cy="14" r="6.2" fill="${hair}" />
        <circle cx="57" cy="14" r="6.2" fill="${hair}" /><circle cx="69" cy="18" r="6" fill="${hair}" />
        <path d="M 31 31 Q 37 36 43 31 Q 49 36 55 31 Q 61 36 68 31" fill="none" stroke="${hair}" stroke-width="4.2" stroke-linecap="round" />
        <path d="M 36 17 Q 50 13 64 17" fill="none" stroke="rgba(255,255,255,0.32)" stroke-width="2.2" stroke-linecap="round" />
      </g>
    `;
  } else if (hairStyle === 'bob') {
    // Tóc Bob ngắn ôm má
    hairSvg = `
      <g class="hair-bob">
        <path d="M 24 51 C 22 25 32 16 50 16 C 68 16 78 25 76 51 C 77 57 72 59 68 56 C 67 43 62 32 50 32 C 38 32 33 43 32 56 C 28 59 23 57 24 51 Z" fill="${hair}" />
        <path d="M 28 32 C 35 34 42 35 50 33 C 58 35 65 34 72 32 C 68 24 60 20 50 20 C 40 20 32 24 28 32 Z" fill="${hair}" />
        <path d="M 32 24 Q 50 19 68 24" fill="none" stroke="rgba(255,255,255,0.3)" stroke-width="2.4" stroke-linecap="round" />
      </g>
    `;
  } else if (hairStyle === 'long') {
    // Tóc dài buông xõa hai vai
    hairSvg = `
      <g class="hair-long">
        <path d="M 23 75 C 20 55 22 28 33 18 C 40 14 60 14 67 18 C 78 28 80 55 77 75 C 74 65 74 48 71 36 C 66 26 58 24 50 24 C 42 24 34 26 29 36 C 26 48 26 65 23 75 Z" fill="${hair}" />
        <path d="M 25 44 C 23 58 24 72 26 80 C 28 72 29 60 29 47 Z" fill="${hair}" />
        <path d="M 75 44 C 77 58 76 72 74 80 C 72 72 71 60 71 47 Z" fill="${hair}" />
        <path d="M 30 35 C 38 38 46 36 50 32 C 54 36 62 38 70 35 C 66 26 58 22 50 22 C 42 22 34 26 30 35 Z" fill="${hair}" />
        <path d="M 35 24 Q 50 19 65 24" fill="none" stroke="rgba(255,255,255,0.3)" stroke-width="2.2" stroke-linecap="round" />
      </g>
    `;
  } else if (hairStyle === 'ponytail') {
    // Tóc đuôi ngựa trẻ trung
    hairSvg = `
      <g class="hair-ponytail">
        <path d="M 68 18 C 78 12 88 18 85 33 C 81 39 74 36 71 28 Z" fill="${hair}" />
        <circle cx="68" cy="22" r="3.2" fill="#F43F5E" />
        <path d="M 24 45 C 22 26 32 16 50 16 C 68 16 76 25 74 45 C 72 36 68 32 62 35 C 56 26 46 24 38 28 C 30 32 26 38 24 45 Z" fill="${hair}" />
        <path d="M 28 34 Q 38 38 48 33 Q 56 37 66 33 Q 58 24 50 23 Q 36 24 28 34 Z" fill="${hair}" />
        <path d="M 33 22 Q 48 18 63 22" fill="none" stroke="rgba(255,255,255,0.3)" stroke-width="2" stroke-linecap="round" />
      </g>
    `;
  } else {
    // Mặc định: Tóc messy thư sinh
    hairSvg = `
      <g class="hair-messy">
        <path d="M 22 44 C 18 28 26 14 50 14 C 74 14 82 28 78 44 C 74 38 72 32 66 36 C 60 26 50 22 42 26 C 32 30 26 36 22 44 Z" fill="${hair}" />
        <path d="M 33 16 Q 40 9 48 14 Q 55 9 62 15" fill="none" stroke="${hair}" stroke-width="4" stroke-linecap="round" />
        <path d="M 24 38 C 26 28 35 24 45 28 C 42 34 36 38 31 40 Z" fill="${hair}" />
        <path d="M 40 27 C 50 24 60 26 65 35 C 58 37 50 35 45 32 Z" fill="${hair}" />
        <path d="M 58 30 C 66 28 73 34 76 41 C 72 39 67 38 64 36 Z" fill="${hair}" />
        <path d="M 34 21 Q 48 16 62 20" fill="none" stroke="rgba(255,255,255,0.3)" stroke-width="2.2" stroke-linecap="round" />
      </g>
    `;
  }

  return `
    <svg viewBox="10 0 80 100" preserveAspectRatio="xMidYMax meet" style="overflow:visible;" class="avatar-chibi-svg">
      <defs>
        <!-- Hào quang nền dịu nhẹ giúp nhân vật nổi bật mềm mại -->
        <radialGradient id="${uid}_halo" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.16"/>
          <stop offset="100%" stop-color="#FFFFFF" stop-opacity="0"/>
        </radialGradient>
      </defs>

      <!-- Hào quang nền êm ái -->
      <circle cx="50" cy="50" r="42" fill="url(#${uid}_halo)" />

      <!-- THÂN & TRANG PHỤC (Đường cong tròn đầy, tự nhiên) -->
      <path d="M 20 86 C 20 74 34 70 50 70 C 66 70 80 74 80 86 L 82 100 L 18 100 Z" fill="${cloth}" />
      <!-- Cổ áo hoodie / áo khoác mềm mại -->
      <path d="M 40 70 C 44 76 50 78 50 78 C 50 78 56 76 60 70 C 56 75 44 75 40 70 Z" fill="rgba(255,255,255,0.18)" />
      <!-- Dây áo hoodie xinh xắn -->
      <path d="M 45 75 Q 44 81 44 84 M 55 75 Q 56 81 56 84" fill="none" stroke="rgba(255,255,255,0.65)" stroke-width="1.6" stroke-linecap="round" />
      <circle cx="44" cy="85.5" r="1.4" fill="rgba(255,255,255,0.9)" />
      <circle cx="56" cy="85.5" r="1.4" fill="rgba(255,255,255,0.9)" />

      <!-- CỔ & BÓNG ĐỔ CẰM TỰ NHIÊN -->
      <path d="M 43 56 C 43 64 45 71 50 71 C 55 71 57 64 57 56 Z" fill="${skin}" />
      <path d="M 44 57 C 47 62 53 62 56 57 Z" fill="rgba(0,0,0,0.07)" />

      <!-- TAI TRÒN DỄ THƯƠNG -->
      <ellipse cx="27" cy="46" rx="4.5" ry="5.5" fill="${skin}" />
      <ellipse cx="27.5" cy="46" rx="2.5" ry="3.2" fill="#FDA4AF" opacity="0.45" />
      <ellipse cx="73" cy="46" rx="4.5" ry="5.5" fill="${skin}" />
      <ellipse cx="72.5" cy="46" rx="2.5" ry="3.2" fill="#FDA4AF" opacity="0.45" />

      <!-- KHUÔN MẶT BẦU BĨNH, THÂN THIỆN -->
      <path d="M 28 41 C 27 27 36 19 50 19 C 64 19 73 27 72 41 C 72 55 62 62 50 62 C 38 62 28 55 28 41 Z" fill="${skin}" />

      <!-- ĐÔI MÁ HỒNG PHỚT SIÊU ĐÁNG YÊU -->
      <ellipse cx="34" cy="49.5" rx="5" ry="2.8" fill="#F43F5E" opacity="0.28" />
      <ellipse cx="66" cy="49.5" rx="5" ry="2.8" fill="#F43F5E" opacity="0.28" />
      <path d="M 32 49 L 34 51 M 35 48.5 L 37 50.5" stroke="#F43F5E" stroke-width="1.1" stroke-linecap="round" opacity="0.4" />
      <path d="M 64 49 L 66 51 M 67 48.5 L 69 50.5" stroke="#F43F5E" stroke-width="1.1" stroke-linecap="round" opacity="0.4" />

      <!-- LÔNG MÀY DỊU DÀNG -->
      <path d="M 35 35.5 Q 40 33 45 35.5" fill="none" stroke="${hair}" stroke-width="2" stroke-linecap="round" opacity="0.85" />
      <path d="M 55 35.5 Q 60 33 65 35.5" fill="none" stroke="${hair}" stroke-width="2" stroke-linecap="round" opacity="0.85" />

      <!-- ĐÔI MẮT LONG LANH, HỒN NHIÊN, CÓ HỒN -->
      <!-- Mi mắt trên cong mượt -->
      <path d="M 34 40.5 C 36 38.5 42 38.5 45 41" fill="none" stroke="#1E293B" stroke-width="2.6" stroke-linecap="round" />
      <path d="M 55 41 C 58 38.5 64 38.5 66 40.5" fill="none" stroke="#1E293B" stroke-width="2.6" stroke-linecap="round" />
      <!-- Tròng mắt to tròn, ấm áp -->
      <ellipse cx="40" cy="44" rx="4.5" ry="5.2" fill="#1E1B4B" />
      <ellipse cx="60" cy="44" rx="4.5" ry="5.2" fill="#1E1B4B" />
      <!-- Sắc xanh lấp lánh bên trong tròng mắt -->
      <ellipse cx="40" cy="45.5" rx="3.6" ry="2.8" fill="#6366F1" opacity="0.45" />
      <ellipse cx="60" cy="45.5" rx="3.6" ry="2.8" fill="#6366F1" opacity="0.45" />
      <!-- Đốm sáng bắt mắt chính (Catchlights) -->
      <circle cx="38.5" cy="42" r="1.7" fill="#FFFFFF" />
      <circle cx="58.5" cy="42" r="1.7" fill="#FFFFFF" />
      <!-- Đốm sáng phụ tạo chiều sâu -->
      <circle cx="41.5" cy="46" r="1" fill="#FFFFFF" opacity="0.85" />
      <circle cx="61.5" cy="46" r="1" fill="#FFFFFF" opacity="0.85" />

      <!-- MŨI NHỎ & NỤ CƯỜI ẤM ÁP -->
      <circle cx="50" cy="48" r="1" fill="#EA580C" opacity="0.3" />
      <path d="M 46.5 53 Q 50 56.5 53.5 53" fill="none" stroke="#E11D48" stroke-width="2" stroke-linecap="round" />

      <!-- TÓC MỀM MẠI, BỒNG BỀNH -->
      ${hairSvg}

      <!-- PHỤ KIỆN XINH XẮN -->
      ${accSvg}
    </svg>
  `;
}
