USE bd_locadora;

-- ====================================================================
-- PARTE 1: VIEWS E ÍNDICES
-- ====================================================================

-- 1.1: Agregação e Abstração com Views

-- View 1: Locações ativas (em andamento)
CREATE OR REPLACE VIEW vw_locacoes_ativas AS
SELECT 
    l.id_locacao,
    c.nome AS cliente,
    v.modelo AS veiculo,
    v.placa,
    l.data_retirada,
    l.data_prevista_devolucao
FROM locacao l
JOIN cliente c ON l.id_cliente = c.id_cliente
JOIN veiculo v ON l.id_veiculo = v.id_veiculo
WHERE l.data_real_devolucao IS NULL;

-- View 2: Veículos disponíveis para locação
CREATE OR REPLACE VIEW vw_veiculos_disponiveis AS
SELECT 
    v.id_veiculo,
    v.modelo,
    v.placa,
    v.ano,
    c.nome_categoria,
    c.valor_diaria
FROM veiculo v
JOIN categoria c ON v.id_categoria = c.id_categoria
WHERE v.status = 'Disponível';

-- View 3: Faturamento agrupado por mês/ano e filial de retirada
CREATE OR REPLACE VIEW vw_faturamento_mensal AS
SELECT 
    YEAR(l.data_retirada) AS ano,
    MONTH(l.data_retirada) AS mes,
    f.id_filial,
    f.nome_filial,
    SUM(l.valor_total) AS faturamento_total
FROM locacao l
JOIN filial f ON l.id_filial_retirada = f.id_filial
WHERE l.valor_total IS NOT NULL
GROUP BY YEAR(l.data_retirada), MONTH(l.data_retirada), f.id_filial, f.nome_filial;


-- 1.2: Análise de Execução e Criação de Índices

-- Consulta A: Busca por CPF
-- [Antes do Índice] (Print do EXPLAIN: type = ALL)
EXPLAIN SELECT * FROM cliente WHERE cpf = '11122233344';

-- Criação do Índice A
CREATE INDEX idx_cliente_cpf ON cliente(cpf);

-- [Depois do Índice] (Print do EXPLAIN: type = const / ref)
EXPLAIN SELECT * FROM cliente WHERE cpf = '11122233344';


-- Consulta B: Filtro por intervalo de datas de retirada
-- [Antes do Índice] (Print do EXPLAIN: type = ALL)
EXPLAIN SELECT * FROM locacao 
WHERE data_retirada BETWEEN '2026-08-01 00:00:00' AND '2026-08-31 23:59:59';

-- Criação do Índice B
CREATE INDEX idx_locacao_data_retirada ON locacao(data_retirada);

-- [Depois do Índice] (Print do EXPLAIN: type = range)
EXPLAIN SELECT * FROM locacao 
WHERE data_retirada BETWEEN '2026-08-01 00:00:00' AND '2026-08-31 23:59:59';


-- Consulta C: Filtro de veículos por categoria
-- [Antes do Índice] (Print do EXPLAIN: type = ALL)
EXPLAIN SELECT * FROM veiculo WHERE id_categoria = 3;

-- Criação do Índice C
CREATE INDEX idx_veiculo_categoria ON veiculo(id_categoria);

-- [Depois do Índice] (Print do EXPLAIN: type = ref)
EXPLAIN SELECT * FROM veiculo WHERE id_categoria = 3;


-- ====================================================================
-- PARTE 2: TRIGGERS, PROCEDURES E FUNCTIONS
-- ====================================================================

-- 2.1: Automação e Auditoria com Triggers

DELIMITER //

-- Trigger 1: Atualiza status para 'locado' na abertura da locação
DROP TRIGGER IF EXISTS trg_locacao_insert_veiculo //
CREATE TRIGGER trg_locacao_insert_veiculo
AFTER INSERT ON locacao
FOR EACH ROW
BEGIN
    UPDATE veiculo 
    SET status = 'locado' 
    WHERE id_veiculo = NEW.id_veiculo;
END //

-- Trigger 2: Restaura status para 'Disponível' no encerramento da locação
DROP TRIGGER IF EXISTS trg_locacao_update_veiculo //
CREATE TRIGGER trg_locacao_update_veiculo
AFTER UPDATE ON locacao
FOR EACH ROW
BEGIN
    IF OLD.data_real_devolucao IS NULL AND NEW.data_real_devolucao IS NOT NULL THEN
        UPDATE veiculo 
        SET status = 'Disponível' 
        WHERE id_veiculo = NEW.id_veiculo;
    END IF;
END //

DELIMITER ;

-- Estrutura da Tabela de Auditoria
DROP TABLE IF EXISTS log_locacao;
CREATE TABLE log_locacao (
    id_log INT PRIMARY KEY AUTO_INCREMENT,
    id_locacao INT NOT NULL,
    valor_antigo DECIMAL(10,2) NULL,
    valor_novo DECIMAL(10,2) NULL,
    status_antigo VARCHAR(30) NULL,
    status_novo VARCHAR(30) NULL,
    usuario VARCHAR(100) NOT NULL,
    data_alteracao DATETIME NOT NULL
);

DELIMITER //

-- Trigger de Auditoria para registrar alterações de valor ou finalização
DROP TRIGGER IF EXISTS trg_locacao_audit //
CREATE TRIGGER trg_locacao_audit
AFTER UPDATE ON locacao
FOR EACH ROW
BEGIN
    DECLARE v_status_antigo VARCHAR(30);
    DECLARE v_status_novo VARCHAR(30);
    
    -- Determina status lógico anterior e atual
    SET v_status_antigo = IF(OLD.data_real_devolucao IS NULL, 'Aberta', 'Finalizada');
    SET v_status_novo   = IF(NEW.data_real_devolucao IS NULL, 'Aberta', 'Finalizada');

    -- Registra apenas se houver mudança de valor ou status de encerramento
    IF (OLD.valor_total <=> NEW.valor_total) = 0 OR (v_status_antigo <> v_status_novo) THEN
        INSERT INTO log_locacao (
            id_locacao, 
            valor_antigo, 
            valor_novo, 
            status_antigo, 
            status_novo, 
            usuario, 
            data_alteracao
        ) VALUES (
            NEW.id_locacao,
            OLD.valor_total,
            NEW.valor_total,
            v_status_antigo,
            v_status_novo,
            CURRENT_USER(),
            NOW()
        );
    END IF;
END //

DELIMITER ;


-- 2.2: Stored Procedures e Functions

DELIMITER //

-- Procedure para abertura atômica de nova locação
DROP PROCEDURE IF EXISTS sp_abrir_locacao //
CREATE PROCEDURE sp_abrir_locacao (
    IN p_id_cliente INT,
    IN p_id_veiculo INT,
    IN p_id_filial INT,
    IN p_dias_locacao INT
)
BEGIN
    DECLARE v_status VARCHAR(30);
    DECLARE v_valor_diaria DECIMAL(8,2);
    DECLARE v_valor_total DECIMAL(10,2);

    -- 1. Validação de disponibilidade do veículo
    SELECT status INTO v_status 
    FROM veiculo 
    WHERE id_veiculo = p_id_veiculo;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Erro: Veículo informado não encontrado.';
    ELSEIF v_status <> 'Disponível' THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Erro: O veículo selecionado não está disponível para locação.';
    END IF;

    -- 2. Busca da diária da categoria
    SELECT c.valor_diaria INTO v_valor_diaria
    FROM veiculo v
    JOIN categoria c ON v.id_categoria = c.id_categoria
    WHERE v.id_veiculo = p_id_veiculo;

    -- 3. Cálculo do valor estimado
    SET v_valor_total = v_valor_diaria * p_dias_locacao;

    -- 4. Inserção na tabela de locações
    INSERT INTO locacao (
        data_retirada, 
        data_prevista_devolucao, 
        data_real_devolucao, 
        valor_total, 
        id_cliente, 
        id_veiculo, 
        id_filial_retirada, 
        id_filial_devolucao
    ) VALUES (
        NOW(),
        DATE_ADD(NOW(), INTERVAL p_dias_locacao DAY),
        NULL,
        v_valor_total,
        p_id_cliente,
        p_id_veiculo,
        p_id_filial,
        p_id_filial
    );

    SELECT 'Locação aberta com sucesso!' AS status, LAST_INSERT_ID() AS id_locacao, v_valor_total AS total_estimado;
END //

-- Function para cálculo de multa por atraso
DROP FUNCTION IF EXISTS fn_calcula_multa //
CREATE FUNCTION fn_calcula_multa (
    p_id_locacao INT, 
    p_taxa_diaria_multa DECIMAL(8,2)
) 
RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
    DECLARE v_data_prevista DATETIME;
    DECLARE v_data_real DATETIME;
    DECLARE v_dias_atraso INT;
    DECLARE v_valor_multa DECIMAL(10,2);

    SELECT data_prevista_devolucao, data_real_devolucao 
    INTO v_data_prevista, v_data_real
    FROM locacao 
    WHERE id_locacao = p_id_locacao;

    -- Se não houver devolução ou se a entrega foi dentro do prazo, multa é zero
    IF v_data_real IS NULL OR v_data_real <= v_data_prevista THEN
        RETURN 0.00;
    END IF;

    -- Diferença de dias entre devolução real e prevista
    SET v_dias_atraso = DATEDIFF(v_data_real, v_data_prevista);

    IF v_dias_atraso > 0 THEN
        SET v_valor_multa = v_dias_atraso * p_taxa_diaria_multa;
    ELSE
        SET v_valor_multa = 0.00;
    END IF;

    RETURN v_valor_multa;
END //

DELIMITER ;
