use std::collections::HashMap;
use std::rc::Rc;

use aries_solver::core::Var;
use aries_solver::model::Label;
use flatzinc::ConstraintItem;
use flatzinc::Expr;
use flatzinc::IntExpr;
use flatzinc::SetLiteralExpr;

use crate::aries::Post;
use crate::aries::constraint::InSet;
use crate::fzn::Fzn;
use crate::fzn::constraint::Constraint;
use crate::fzn::constraint::Encode;
use crate::fzn::domain::IntSet;
use crate::fzn::model::Model;
use crate::fzn::parser::var_int_from_expr;
use crate::fzn::types::Int;
use crate::fzn::var::VarInt;

/// Set membership constraint.
///
/// ```flatzinc
/// constraint set_in(x, {1, 3, 5});
/// % x in {1, 3, 5}
/// ```
#[derive(Clone, Debug)]
pub struct SetIn {
    x: Rc<VarInt>,
    set: SetLiteral,
}

/// Constant set given to a [SetIn] constraint.
#[derive(Clone, Debug)]
pub enum SetLiteral {
    /// Enumerated set of values, e.g. `{1, 3, 5}`.
    Values(IntSet),
    /// Contiguous range, e.g. `2..5`.
    Range(Int, Int),
}

impl SetLiteral {
    fn fzn(&self) -> String {
        match self {
            SetLiteral::Values(set) => format!(
                "{{{}}}",
                set.iter()
                    .map(|v| v.fzn())
                    .collect::<Vec<String>>()
                    .join(", "),
            ),
            SetLiteral::Range(lb, ub) => format!("{}..{}", lb.fzn(), ub.fzn()),
        }
    }

    fn from_expr(expr: &Expr) -> anyhow::Result<Self> {
        match expr {
            Expr::Set(SetLiteralExpr::SetInts(values)) => {
                let ints: anyhow::Result<Vec<Int>> = values
                    .iter()
                    .map(|e| int_from_int_expr(e, "set value"))
                    .collect();
                let set = IntSet::from_iter(ints?);
                anyhow::ensure!(!set.is_empty(), "empty set");
                Ok(SetLiteral::Values(set))
            }
            Expr::Set(SetLiteralExpr::IntInRange(lb, ub)) => {
                let lb = int_from_int_expr(lb, "set lower bound")?;
                let ub = int_from_int_expr(ub, "set upper bound")?;
                anyhow::ensure!(lb <= ub, "invalid range {}..{}", lb, ub);
                Ok(SetLiteral::Range(lb, ub))
            }
            _ => anyhow::bail!("not a set literal"),
        }
    }
}

fn int_from_int_expr(e: &IntExpr, what: &str) -> anyhow::Result<Int> {
    match e {
        IntExpr::Int(x) => Ok(*x as Int),
        IntExpr::VarParIdentifier(_) => {
            anyhow::bail!("{} must be a constant integer", what)
        }
    }
}

impl SetIn {
    pub const NAME: &str = "set_in";
    pub const NB_ARGS: usize = 2;

    pub fn new(x: Rc<VarInt>, set: SetLiteral) -> Self {
        Self { x, set }
    }

    pub fn x(&self) -> &Rc<VarInt> {
        &self.x
    }

    pub fn set(&self) -> &SetLiteral {
        &self.set
    }

    pub fn try_from_item(
        item: ConstraintItem,
        model: &mut Model,
    ) -> anyhow::Result<Self> {
        anyhow::ensure!(
            item.id.as_str() == Self::NAME,
            "'{}' expected but received '{}'",
            Self::NAME,
            item.id,
        );
        anyhow::ensure!(
            item.exprs.len() == Self::NB_ARGS,
            "{} args expected but received {}",
            Self::NB_ARGS,
            item.exprs.len(),
        );
        let x = var_int_from_expr(&item.exprs[0], model)?;
        let set = SetLiteral::from_expr(&item.exprs[1])?;
        Ok(Self::new(x, set))
    }
}

impl Fzn for SetIn {
    fn fzn(&self) -> String {
        format!("{}({:?}, {});\n", Self::NAME, self.x.fzn(), self.set.fzn())
    }
}

impl TryFrom<Constraint> for SetIn {
    type Error = anyhow::Error;

    fn try_from(value: Constraint) -> Result<Self, Self::Error> {
        match value {
            Constraint::SetIn(c) => Ok(c),
            _ => anyhow::bail!("unable to downcast to {}", Self::NAME),
        }
    }
}

impl From<SetIn> for Constraint {
    fn from(value: SetIn) -> Self {
        Self::SetIn(value)
    }
}

/// Range membership constraint.
///
/// `lb <= x <= ub`
struct InRange {
    var: Var,
    lb: Int,
    ub: Int,
}

impl InRange {
    fn new(var: Var, lb: Int, ub: Int) -> Self {
        Self { var, lb, ub }
    }
}

impl<Lbl: Label> Post<Lbl> for InRange {
    fn post(&self, model: &mut aries_solver::model::Model<Lbl>) {
        model.enforce(self.var.geq(self.lb));
        model.enforce(self.var.leq(self.ub));
    }
}

impl Encode for SetIn {
    fn encode(
        &self,
        translation: &HashMap<usize, Var>,
    ) -> Box<(dyn Post<usize>)> {
        let x = *translation.get(self.x.id()).unwrap();
        match &self.set {
            SetLiteral::Values(set) => {
                Box::new(InSet::new(x, set.values().clone()))
            }
            SetLiteral::Range(lb, ub) => Box::new(InRange::new(x, *lb, *ub)),
        }
    }
}
