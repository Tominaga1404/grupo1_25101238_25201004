-- Views
-- Lista as locações que estão em andamento

CREATE VIEW vw_locacoes_ativas AS
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

-- Exibe todos os veículos prontos para locação

CREATE VIEW vw_veiculos_disponiveis AS
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

-- Soma o valor total das locações finalizadas

CREATE VIEW vw_faturamento_mensal AS
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

-- Consultas
-- Para ver todas as locações ativas:
SELECT * FROM vw_locacoes_ativas;

-- Para ver apenas os veículos da categoria SUV que estão disponíveis:
SELECT * FROM vw_veiculos_disponiveis 
WHERE nome_categoria = 'SUV';

-- Para ver o faturamento ordenado do mais recente para o mais antigo:
SELECT * FROM vw_faturamento_mensal 
ORDER BY ano DESC, mes DESC;

-- Consulta A: Busca de cliente por número de CPF (antes do índice)
SELECT * FROM cliente WHERE cpf = '11122233344';

-- Índice
CREATE INDEX idx_cliente_cpf ON cliente(cpf);

-- Consulta A: Busca de cliente por número de CPF (depois do índice)
SELECT * FROM cliente WHERE cpf = '11122233344';

-- Consulta B: Busca de locações filtradas por intervalo de datas de retirada (antes do índice)
SELECT * FROM locacao 
WHERE data_retirada BETWEEN '2026-08-01 00:00:00' AND '2026-08-31 23:59:59';

-- Índice
CREATE INDEX idx_locacao_data_retirada ON locacao(data_retirada);

-- Consulta B: Busca de locações filtradas por intervalo de datas de retirada (depois do índice)
SELECT * FROM locacao 
WHERE data_retirada BETWEEN '2026-08-01 00:00:00' AND '2026-08-31 23:59:59';

-- Consulta C: Filtro de veículos por categoria (antes do índice)
SELECT * FROM veiculo WHERE id_categoria = 3;

-- Índice
CREATE INDEX idx_veiculo_categoria ON veiculo(id_categoria);

-- Consulta C: Filtro de veículos por categoria (depois do índice)
SELECT * FROM veiculo WHERE id_categoria = 3;

-- Pergunta de reflexão (incluir no relatório)
-- Em que situações a presença de múltiplos índices pode prejudicar o desempenho do banco de dados (ex: tabelas com alta taxa de INSERT, UPDATE ou DELETE)?
-- A presença de muitos índices pode prejudicar o desempenho em tabelas com muitas operações de escrita (INSERT, UPDATE e DELETE), por causa do custo de 
-- manutenção das árvores (B-Trees), pela geração da contenção de I/O e alto consumo de processador e pelo desperdício de espaço em disco

-- Triggers

DELIMITER //

-- Gatilho 1: Altera o status para 'Alugado' ao inserir uma nova locação
CREATE TRIGGER trg_locacao_insert_veiculo
AFTER INSERT ON locacao
FOR EACH ROW
BEGIN
    UPDATE veiculo 
    SET status = 'Alugado' 
    WHERE id_veiculo = NEW.id_veiculo;
END//

-- Gatilho 2: Altera o status para 'Disponível' quando a devolução é realizada
CREATE TRIGGER trg_locacao_update_veiculo
AFTER UPDATE ON locacao
FOR EACH ROW
BEGIN
    -- Verifica se a locação foi encerrada (antes nula e agora preenchida)
    IF OLD.data_real_devolucao IS NULL AND NEW.data_real_devolucao IS NOT NULL THEN
        UPDATE veiculo 
        SET status = 'Disponível' 
        WHERE id_veiculo = NEW.id_veiculo;
    END IF;
END//

DELIMITER ;

-- Tabela de Auditoria
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

-- Trigger da Auditoria 
DELIMITER //

CREATE TRIGGER trg_locacao_audit
AFTER UPDATE ON locacao
FOR EACH ROW
BEGIN
    DECLARE v_status_antigo VARCHAR(30);
    DECLARE v_status_novo VARCHAR(30);
    
    -- Define o status lógico anterior com base na data de devolução
    IF OLD.data_real_devolucao IS NULL THEN
        SET v_status_antigo = 'Ativa';
    ELSE
        SET v_status_antigo = 'Finalizada';
    END IF;
    
    -- Define o status lógico novo com base na data de devolução
    IF NEW.data_real_devolucao IS NULL THEN
        SET v_status_novo = 'Ativa';
    ELSE
        SET v_status_novo = 'Finalizada';
    END IF;

    -- Registra no log apenas se houver alteração no valor total ou no status lógico
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
END//

DELIMITER ;

-- Procedures

-- Automatiza o processo de abertura de uma nova locação
DELIMITER //

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

    -- 1. Valida se o veículo está disponível
    SELECT status INTO v_status 
    FROM veiculo 
    WHERE id_veiculo = p_id_veiculo;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Erro: Veículo não encontrado.';
    ELSEIF v_status <> 'Disponível' THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Erro: O veículo selecionado não está disponível para locação.';
    END IF;

    -- 2. Busca a taxa diária associada à categoria do veículo
    SELECT c.valor_diaria INTO v_valor_diaria
    FROM veiculo v
    JOIN categoria c ON v.id_categoria = c.id_categoria
    WHERE v.id_veiculo = p_id_veiculo;

    -- 3. Calcula o valor total da locação
    SET v_valor_total = v_valor_diaria * p_dias_locacao;

    -- 4. Realiza o INSERT na tabela de locações
    -- (Definimos a filial de retirada e devolução inicialmente como a mesma informada)
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

    SELECT 'Locação aberta com sucesso!' AS mensagem, v_valor_total AS valor_estimado;
END//

DELIMITER ;

-- Chamada da Procedure
-- Abre uma locação para o cliente 2, veículo 2, na filial 1, por 4 dias
CALL sp_abrir_locacao(2, 2, 1, 4);

-- Function
-- Calcula o valor da multa por atraso na devolução de um veículo

DELIMITER //

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

    -- Busca as datas da locação informada
    SELECT data_prevista_devolucao, data_real_devolucao 
    INTO v_data_prevista, v_data_real
    FROM locacao 
    WHERE id_locacao = p_id_locacao;

    -- Se a locação ainda não foi devolvida (NULL) ou não houve atraso, retorna 0
    IF v_data_real IS NULL OR v_data_real <= v_data_prevista THEN
        RETURN 0.00;
    END IF;

    -- Calcula a diferença de dias entre a devolução real e a prevista
    SET v_dias_atraso = DATEDIFF(v_data_real, v_data_prevista);

    -- Calcula o valor total da multa
    SET v_valor_multa = v_dias_atraso * p_taxa_diaria_multa;

    RETURN v_valor_multa;
END//

DELIMITER ;

-- Chamada da Function
-- Calcula a multa para a locação ID 2 considerando uma taxa de R$ 50,00 por dia de atraso
SELECT 
    id_locacao, 
    data_prevista_devolucao, 
    data_real_devolucao, 
    fn_calcula_multa(id_locacao, 50.00) AS valor_multa
FROM locacao 
WHERE id_locacao = 2;
