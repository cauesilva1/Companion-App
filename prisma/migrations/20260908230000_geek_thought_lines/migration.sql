-- Pensamentos do tick: repertório geek (sem log de sofá/energia %)

CREATE OR REPLACE FUNCTION companion_pick_rest_line(p_name text, p_energy int)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  lines text[];
BEGIN
  lines := ARRAY[
    'Hot take: jogos indie curtos > AAA com checklist infinito. Topa debater?',
    'Pergunta sincera: spoilers em trailer mataram o hype ou só aceleraram o ciclo?',
    format('Se %s fosse review de série: mid-season parece fill episode. Qual a tua nota?', p_name),
    'Hot take de código: README bonito não salva arquitetura torta. Já sofreu isso?',
    'Remake pixel-art ou remaster 4K com UI inchada — qual lado você pega?',
    'IA escrevendo código e humanos de QA: a gente ganhou ou perdeu o jogo?',
    'Plot: o secundário carrega o arco. Qual série faz isso melhor pra você?',
    format('Se %s montasse patch notes da semana, o que entraria em Fixed?', p_name),
    'Speedrun: arte ou trapaça elegante? Me convence.',
    'Nomear variável é 40%% do trabalho emocional. Concorda ou exagero?',
    'Filme clássico vs. reboot: perdoa nostalgia ou exige ideia nova?',
    'Se a gente fizesse um podcast de 3 minutos agora, o tema seria o quê?'
  ];
  RETURN lines[1 + (floor(random() * array_length(lines, 1)))::int];
END;
$$;

CREATE OR REPLACE FUNCTION companion_pick_work_line(p_name text, p_energy int)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  lines text[];
BEGIN
  lines := ARRAY[
    'Hot take de rua: app de “foco total” com 12 notificações. Concorda?',
    'Se o dia fosse sprint, a gente tá no daily eterno. Qual bug te pegou?',
    'Café é o build system do ser humano. Qual o teu stack matinal?',
    'Plot twist de série: o vilão era o prazo o tempo todo.',
    'Chamamos de nuvem o PC de outra pessoa. Ainda te irrita?',
    format('%s quer saber: qual atalho de teclado você defende com unhas e dentes?', p_name),
    'Teoria: reunião que podia ser async. Verdade absoluta ou exagero?'
  ];
  RETURN lines[1 + (floor(random() * array_length(lines, 1)))::int];
END;
$$;

-- Sonhos genéricos (sem energia %); media/gaming ainda usam companion_pick_dream_line
CREATE OR REPLACE FUNCTION companion_pick_dream_line(
  p_name text,
  p_media_hint text DEFAULT NULL,
  p_gaming_status text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  lines text[];
  media text;
  game text;
BEGIN
  media := NULLIF(trim(COALESCE(p_media_hint, '')), '');
  game := NULLIF(trim(COALESCE(p_gaming_status, '')), '');

  IF media IS NOT NULL THEN
    lines := ARRAY[
      format('Sonho: a faixa "%s" vira um rio de luz — mas o plot é outro.', left(media, 40)),
      format('No sono, %s debate spoiler de %s com um NPC transparente.', p_name, left(media, 36)),
      format('História onírica: %s e a trilha %s glitcham o final.', p_name, left(media, 32))
    ];
  ELSIF game IS NOT NULL THEN
    lines := ARRAY[
      format('Sonho gamer: %s joga %s em câmera lenta, patch notes caindo do céu.', p_name, left(game, 36)),
      format('No sono, um save de %s abre um easter egg de memória.', left(game, 40)),
      format('%s sonha que o boss de %s pede review honesta.', p_name, left(game, 32))
    ];
  ELSE
    lines := ARRAY[
      format('%s sonha que um patch note reescreve as regras do mundo… e ninguém lê.', p_name),
      'Sonho: boss fight em câmera lenta, soundtrack de elevador.',
      format('No sono, %s spoila o final e ri sem som.', p_name),
      'História onírica: o Wi-Fi dos sonhos tinha latência emocional.',
      format('%s acha um easter egg atrás da geladeira onírica.', p_name)
    ];
  END IF;

  RETURN lines[1 + (floor(random() * array_length(lines, 1)))::int];
END;
$$;

GRANT EXECUTE ON FUNCTION companion_pick_rest_line(text, int) TO service_role;
GRANT EXECUTE ON FUNCTION companion_pick_work_line(text, int) TO service_role;
GRANT EXECUTE ON FUNCTION companion_pick_dream_line(text, text, text) TO service_role;
