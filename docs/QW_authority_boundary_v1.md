# Q/W Authority Boundary v1

Status: LOCKED
Checkpoint: QW_authority_model_v1_defined (id=17)
Date: 2026-06-07

---

Q is the canonical core pool.
W is the shared working / communication pool.

Q -> W is allowed as controlled publication.
W -> Q direct write is not allowed.

At the current stage, W->Q data backflow does not exist.
No q_absorption_queue table or W->Q sync script is required.

If future W->Q backflow is introduced, it must enter Q only through a controlled absorption filter.
W-side data may become candidate input, but must not directly overwrite Q core tables,
checkpoints, function snapshots, forecast outputs, or decision outputs.

---

Q 是标准内核池。
W 是共享工作池 / 展示交流池。

Q -> W 允许，作为受控发布。
W -> Q 不允许直接写入。

当前阶段不存在实际 W->Q 数据回流。
因此不创建 q_absorption_queue 表，也不编写 W->Q 回流脚本。

如果未来引入 W->Q 回流，必须先经过受控吸收筛网。
W 侧数据只能作为候选输入，不得直接覆盖 Q 的核心表、checkpoint、
function snapshot、forecast output 或 decision output。
